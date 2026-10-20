#import "WazeHUDPrefsRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <objc/runtime.h>
#import <sys/wait.h>
#import <signal.h>
#import <sys/stat.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.quanlee.wazehud.plist"
#define PREFS_SUITE @"com.quanlee.wazehud"
#define PID_FILE_PATH @"/var/mobile/wazehud.pid"

static inline NSString *getWazeHUDDir() {
	if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/Library/WazeHUD"]) {
		return @"/var/jb/Library/WazeHUD";
	}
	return @"/Library/WazeHUD";
}
#define WAZEHUD_DIR getWazeHUDDir()

@interface WazeHUDPrefsRootListController ()
@property (nonatomic, assign) BOOL isPickingHTML;
@end

@implementation WazeHUDPrefsRootListController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"WazeHUD Pro v2.0.0";
}

- (NSString *)getVersionString:(PSSpecifier *)specifier {
	return @"v2.0.0";
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

// MARK: - Helper đọc / ghi cấu hình
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	if (!key) return [super readPreferenceValue:specifier];

	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	id val = [defaults objectForKey:key];
	if (val) return val;

	NSDictionary *filePrefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
	if (filePrefs && filePrefs[key]) return filePrefs[key];

	return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	[super setPreferenceValue:value specifier:specifier];

	if (!key) return;

	// Lưu đồng thời vào NSUserDefaults và file .plist để server.py đọc được
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	[defaults setObject:value forKey:key];
	[defaults synchronize];

	NSMutableDictionary *filePrefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
	filePrefs[key] = value;
	[filePrefs writeToFile:PREFS_PATH atomically:YES];

	// TỰ ĐỘNG BẬT/TẮT SERVER NGAY KHI GẠT SWITCH "isEnabled"
	if ([key isEqualToString:@"isEnabled"]) {
		BOOL enabled = [value boolValue];
		if (enabled) {
			[self startServer];
		} else {
			[self stopServer];
		}
	}
}

// MARK: - Bật & Tắt Server triệt để
- (void)stopServer {
	// 1. Kill tiến trình trực tiếp bằng syscall kill(SIGKILL) qua PID file
	NSString *pidStr = [NSString stringWithContentsOfFile:PID_FILE_PATH encoding:NSUTF8StringEncoding error:nil];
	if (pidStr) {
		pid_t p = (pid_t)[pidStr integerValue];
		if (p > 0) {
			kill(p, SIGKILL);
		}
		[[NSFileManager defaultManager] removeItemAtPath:PID_FILE_PATH error:nil];
	}

	// 2. Chạy wazehud-ctrl stop để quét dọn sạch sẽ bất kỳ tiến trình python nào còn sót
	[self runControlScriptWithAction:@"stop" httpPort:nil wsPort:nil];
}

- (void)startServer {
	// Cập nhật IP hiện tại vào plist để server.py đọc ngay lập tức
	NSString *currentIP = [self getIPAddress:nil];
	NSMutableDictionary *filePrefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
	if (currentIP && ![currentIP isEqualToString:@"127.0.0.1"] && ![currentIP hasPrefix:@"Không"]) {
		filePrefs[@"deviceIP"] = currentIP;
		[filePrefs writeToFile:PREFS_PATH atomically:YES];
	}

	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	NSString *httpPort = [defaults stringForKey:@"httpPort"] ?: (filePrefs[@"httpPort"] ?: @"8080");
	NSString *wsPort   = [defaults stringForKey:@"wsPort"]   ?: (filePrefs[@"wsPort"]   ?: @"8765");

	[self runControlScriptWithAction:@"restart" httpPort:httpPort wsPort:wsPort];
}

// MARK: - Quản lý tiến trình qua script wazehud-ctrl
- (int)runControlScriptWithArgs:(NSArray<NSString *> *)argsList {
	const char *shellPath = "/bin/sh";
	if (access(shellPath, X_OK) != 0) {
		shellPath = "/var/jb/bin/sh";
	}
	const char *scriptPath = "/var/jb/usr/bin/wazehud-ctrl";
	if (access(scriptPath, X_OK) != 0) {
		scriptPath = "/usr/bin/wazehud-ctrl";
	}

	char *const customEnv[] = {
		"PATH=/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/local/bin:/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin",
		"HOME=/var/mobile",
		NULL
	};

	NSUInteger count = argsList.count;
	const char **args = (const char **)malloc(sizeof(char *) * (count + 3));
	args[0] = shellPath;
	args[1] = scriptPath;
	for (NSUInteger i = 0; i < count; i++) {
		args[i + 2] = [argsList[i] UTF8String];
	}
	args[count + 2] = NULL;

	pid_t pid = 0;
	int ret = posix_spawn(&pid, shellPath, NULL, NULL, (char *const *)args, customEnv);
	free(args);

	if (ret == 0 && pid > 0) {
		int status;
		waitpid(pid, &status, 0);
	}

	return ret;
}

- (int)runControlScriptWithAction:(NSString *)action httpPort:(NSString *)httpPort wsPort:(NSString *)wsPort {
	if ([action isEqualToString:@"restart"] || [action isEqualToString:@"start"]) {
		NSString *hp = httpPort ?: @"8080";
		NSString *wp = wsPort ?: @"8765";
		return [self runControlScriptWithArgs:@[@"restart", hp, wp]];
	} else {
		return [self runControlScriptWithArgs:@[@"stop"]];
	}
}

// MARK: - Hàm lấy IP thiết bị
- (NSString *)getIPAddress:(PSSpecifier *)specifier {
	NSString *wifiIP = nil;
	NSString *otherIP = nil;
	struct ifaddrs *interfaces = NULL;
	if (getifaddrs(&interfaces) == 0) {
		struct ifaddrs *temp = interfaces;
		while (temp != NULL) {
			if (temp->ifa_addr != NULL && temp->ifa_addr->sa_family == AF_INET) {
				if (!(temp->ifa_flags & IFF_LOOPBACK) && (temp->ifa_flags & IFF_UP)) {
					NSString *ip = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
					if (![ip hasPrefix:@"127."]) {
						NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
						if ([name isEqualToString:@"en0"] || [name isEqualToString:@"ap1"] || [name isEqualToString:@"bridge100"]) {
							wifiIP = ip;
							break;
						} else if (!otherIP) {
							otherIP = ip;
						}
					}
				}
			}
			temp = temp->ifa_next;
		}
		freeifaddrs(interfaces);
	}
	return wifiIP ?: (otherIP ?: @"127.0.0.1");
}

// MARK: - Mở Web HUD
- (void)openWeb {
	[self openWeb:nil];
}

- (void)openWeb:(PSSpecifier *)specifier {
	NSIndexPath *selectedIndexPath = [self.table indexPathForSelectedRow];
	if (selectedIndexPath) {
		[self.table deselectRowAtIndexPath:selectedIndexPath animated:YES];
	}

	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	BOOL isEnabled = [defaults boolForKey:@"isEnabled"];
	if (!isEnabled) {
		[self showAlertWithTitle:@"Server Đang Tắt" message:@"Vui lòng gạt BẬT 'Server WazeHUD' trước khi mở web!"];
		return;
	}

	NSString *port = [defaults stringForKey:@"httpPort"];
	if (!port || [port length] == 0) {
		NSDictionary *filePrefs = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
		port = filePrefs[@"httpPort"] ?: @"8080";
	}

	// Đảm bảo server đang chạy
	[self startServer];

	NSString *urlStr = [NSString stringWithFormat:@"http://127.0.0.1:%@", port];
	NSURL *url = [NSURL URLWithString:urlStr];
	if (!url) return;

	dispatch_async(dispatch_get_main_queue(), ^{
		if ([[UIApplication sharedApplication] respondsToSelector:@selector(openURL:options:completionHandler:)]) {
			[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
		} else {
			Class workspaceClass = objc_getClass("LSApplicationWorkspace");
			if (workspaceClass) {
				id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
				if ([workspace respondsToSelector:@selector(openURL:)]) {
					[workspace performSelector:@selector(openURL:) withObject:url];
				}
			}
		}
	});
}

// MARK: - Lưu & Khởi Động Lại Server
- (void)applyAndRestart {
	[self applyAndRestart:nil];
}

- (void)applyAndRestart:(PSSpecifier *)specifier {
	[self.view endEditing:YES];

	NSIndexPath *selectedIndexPath = [self.table indexPathForSelectedRow];
	if (selectedIndexPath) {
		[self.table deselectRowAtIndexPath:selectedIndexPath animated:YES];
	}

	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	[defaults synchronize];

	NSString *httpPort = [defaults stringForKey:@"httpPort"] ?: @"8080";
	NSString *wsPort   = [defaults stringForKey:@"wsPort"]   ?: @"8765";
	BOOL isEnabled     = [defaults boolForKey:@"isEnabled"];

	NSMutableDictionary *filePrefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
	filePrefs[@"httpPort"] = httpPort;
	filePrefs[@"wsPort"] = wsPort;
	filePrefs[@"isEnabled"] = @(isEnabled);
	[filePrefs writeToFile:PREFS_PATH atomically:YES];

	if (isEnabled) {
		[self startServer];
		[self showAlertWithTitle:@"WazeHUD Pro" message:[NSString stringWithFormat:@"Đã lưu & BẬT Server thành công!\nCổng Web (HTTP): %@\nCổng Mod (WS): %@", httpPort, wsPort]];
	} else {
		[self stopServer];
		[self showAlertWithTitle:@"WazeHUD Pro" message:@"Đã dừng Server WazeHUD thành công!"];
	}
}

// MARK: - Chọn & Cập Nhật File (HTML / Python) từ Ứng dụng Tệp (Files)

- (void)pickHTMLFile {
	[self pickHTMLFile:nil];
}

- (void)pickHTMLFile:(PSSpecifier *)specifier {
	self.isPickingHTML = YES;
	[self presentFilePicker];
}

- (void)pickPythonFile {
	[self pickPythonFile:nil];
}

- (void)pickPythonFile:(PSSpecifier *)specifier {
	self.isPickingHTML = NO;
	[self presentFilePicker];
}

- (void)presentFilePicker {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	NSArray *types = @[
		@"public.data",
		@"public.item",
		@"public.content",
		@"public.plain-text",
		@"public.html",
		@"public.python-script"
	];
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;

	UIViewController *topVC = self;
	while (topVC.presentedViewController) {
		topVC = topVC.presentedViewController;
	}
	[topVC presentViewController:picker animated:YES completion:nil];
}

// Delegate nhận file từ Document Picker
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (urls.count == 0) return;
	NSURL *sourceURL = urls.firstObject;

	BOOL shouldAccess = [sourceURL startAccessingSecurityScopedResource];

	NSString *fileName = self.isPickingHTML ? @"index.html" : @"server.py";
	NSString *destPath = [WAZEHUD_DIR stringByAppendingPathComponent:fileName];
	NSString *tempPath = @"/var/mobile/wazehud_temp_import.dat";

	NSError *error = nil;
	NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&error];

	if (shouldAccess) {
		[sourceURL stopAccessingSecurityScopedResource];
	}

	if (data && data.length > 0) {
		// 1. Ghi vào file tạm của user mobile
		[data writeToFile:tempPath atomically:YES];

		// 2. Gọi script wazehud-ctrl để cài đặt file vào thư mục đích với full quyền
		[self runControlScriptWithArgs:@[@"install-file", tempPath, fileName]];

		// 3. Dự phòng ghi trực tiếp nếu có quyền
		[[NSFileManager defaultManager] createDirectoryAtPath:WAZEHUD_DIR withIntermediateDirectories:YES attributes:nil error:nil];
		[data writeToFile:destPath atomically:YES];
		[[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0666} ofItemAtPath:destPath error:nil];

		// 4. Kiểm tra file sau khi cài
		NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:destPath error:nil];
		if (attrs && [attrs fileSize] > 0) {
			NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
			if (!self.isPickingHTML && [defaults boolForKey:@"isEnabled"]) {
				[self startServer];
			}

			[self showAlertWithTitle:@"Thành Công" message:[NSString stringWithFormat:@"Đã cập nhật file '%@' thành công! (Dung lượng: %lu bytes)", fileName, (unsigned long)[attrs fileSize]]];
		} else {
			[self showAlertWithTitle:@"Lỗi Ghi File" message:[NSString stringWithFormat:@"Không thể ghi vào đường dẫn: %@", destPath]];
		}
	} else {
		[self showAlertWithTitle:@"Lỗi Đọc File" message:[NSString stringWithFormat:@"Không đọc được dữ liệu: %@", error ? error.localizedDescription : @"File rỗng (0 bytes)"]];
	}
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	// Người dùng huỷ chọn file, không làm gì
}

// MARK: - Khôi phục File gốc mặc định
- (void)restoreDefaultFiles {
	[self restoreDefaultFiles:nil];
}

- (void)restoreDefaultFiles:(PSSpecifier *)specifier {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *htmlDefault = [WAZEHUD_DIR stringByAppendingPathComponent:@"index.html.default"];
	NSString *pyDefault   = [WAZEHUD_DIR stringByAppendingPathComponent:@"server.py.default"];

	NSString *htmlDest = [WAZEHUD_DIR stringByAppendingPathComponent:@"index.html"];
	NSString *pyDest   = [WAZEHUD_DIR stringByAppendingPathComponent:@"server.py"];

	// 1. Gọi script wazehud-ctrl restore để chép lại file gốc
	[self runControlScriptWithArgs:@[@"restore"]];

	// 2. Chép trực tiếp bổ trợ nếu có quyền
	if ([fm fileExistsAtPath:htmlDefault]) {
		[fm removeItemAtPath:htmlDest error:nil];
		[fm copyItemAtPath:htmlDefault toPath:htmlDest error:nil];
		[fm setAttributes:@{NSFilePosixPermissions: @0666} ofItemAtPath:htmlDest error:nil];
	}
	if ([fm fileExistsAtPath:pyDefault]) {
		[fm removeItemAtPath:pyDest error:nil];
		[fm copyItemAtPath:pyDefault toPath:pyDest error:nil];
		[fm setAttributes:@{NSFilePosixPermissions: @0666} ofItemAtPath:pyDest error:nil];
	}

	BOOL okHtml = [fm fileExistsAtPath:htmlDest];
	BOOL okPy   = [fm fileExistsAtPath:pyDest];

	// Restart server nếu đang bật
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_SUITE];
	if ([defaults boolForKey:@"isEnabled"]) {
		[self startServer];
	}

	if (okHtml && okPy) {
		[self showAlertWithTitle:@"Khôi Phục Thành Công" message:@"Đã khôi phục file index.html và server.py về trạng thái gốc của tweak!"];
	} else {
		[self showAlertWithTitle:@"Thông Báo" message:@"Không tìm thấy file backup gốc (.default) trong thư mục WazeHUD."];
	}
}

// MARK: - Helper hiển thị Alert
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)msg {
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			UIAlertController *alert = [UIAlertController
				alertControllerWithTitle:title
				message:msg
				preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:@"OK"
				style:UIAlertActionStyleDefault handler:nil]];

			UIViewController *topVC = self;
			while (topVC.presentedViewController) {
				topVC = topVC.presentedViewController;
			}
			[topVC presentViewController:alert animated:YES completion:nil];
		} @catch (NSException *e) {
			NSLog(@"[WazeHUD] Exception showing alert: %@", e);
		}
	});
}

@end