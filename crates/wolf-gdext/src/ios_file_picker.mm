#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

extern "C" void wolf_gdext_ios_picker_result(const char *path, int status);

typedef NS_ENUM(NSInteger, WolfFilePickerMode) {
	WolfFilePickerModeImport = 0,
	WolfFilePickerModeExport = 1,
};

@protocol WolfFilePickerWindowDelegate <NSObject>
@property(nonatomic, readonly, strong) UIWindow *window;
@end

@interface WolfFilePickerDelegate : NSObject <UIDocumentPickerDelegate,
		UIAdaptivePresentationControllerDelegate>
@property(nonatomic, assign) WolfFilePickerMode mode;
@property(nonatomic, copy) NSString *exportTempDir;
- (void)finishWithStatus:(int)status path:(NSString *)path;
@end

static WolfFilePickerDelegate *g_activePicker = nil;

static UIViewController *WolfRootViewController(void) {
	UIWindow *window = nil;
	id delegate = UIApplication.sharedApplication.delegate;
	if ([delegate respondsToSelector:@selector(window)]) {
		window = [(id<WolfFilePickerWindowDelegate>)delegate window];
	}
	if (!window) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:[UIWindowScene class]]) {
				continue;
			}
			for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
				if (candidate.isKeyWindow) {
					window = candidate;
					break;
				}
			}
			if (window) {
				break;
			}
		}
	}
	UIViewController *controller = window.rootViewController;
	while (controller.presentedViewController) {
		controller = controller.presentedViewController;
	}
	return controller;
}

static NSError *WolfPickerError(NSString *message) {
	return [NSError errorWithDomain:@"ImoutoLifeFilePicker"
		code:1
		userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSString *WolfCopyIntoAppTemp(NSURL *source, NSError **error) {
	BOOL scoped = [source startAccessingSecurityScopedResource];
	// The directory bit is only reliable inside the security scope: for a
	// document-provider URL the path is not readable before the grant.
	NSNumber *isDirectory = nil;
	[source getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
	if (isDirectory.boolValue) {
		if (scoped) {
			[source stopAccessingSecurityScopedResource];
		}
		if (error) {
			*error = WolfPickerError(@"请选择存档文件，而不是文件夹。");
		}
		return nil;
	}
	NSString *name = source.lastPathComponent.length ? source.lastPathComponent : @"import.sav";
	NSString *destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"ImoutoLife-import-%@-%@", NSUUID.UUID.UUIDString, name]];
	BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:source
		toURL:[NSURL fileURLWithPath:destination]
		error:error];
	if (scoped) {
		[source stopAccessingSecurityScopedResource];
	}
	return copied ? destination : nil;
}

static void WolfReportError(NSString *message) {
	const char *text = message.length ? message.UTF8String : "iOS 文件选择器不可用。";
	wolf_gdext_ios_picker_result(text ? text : "", 2);
}

@implementation WolfFilePickerDelegate

- (void)finishWithStatus:(int)status path:(NSString *)path {
	if (g_activePicker != self) {
		return;
	}
	g_activePicker = nil;
	if (self.exportTempDir.length) {
		[[NSFileManager defaultManager] removeItemAtPath:self.exportTempDir error:nil];
		self.exportTempDir = nil;
	}
	const char *text = path.length ? path.UTF8String : "";
	wolf_gdext_ios_picker_result(text ? text : "", status);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	[self finishWithStatus:1 path:nil];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
	[self finishWithStatus:1 path:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
		didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (self.mode == WolfFilePickerModeExport) {
		[self finishWithStatus:0 path:urls.firstObject.path];
		return;
	}

	NSURL *source = urls.firstObject;
	if (!source) {
		[self finishWithStatus:2 path:@"没有选择存档文件。"];
		return;
	}
	NSError *error = nil;
	NSString *copied = WolfCopyIntoAppTemp(source, &error);
	if (!copied) {
		[self finishWithStatus:2 path:error.localizedDescription ?: @"无法读取所选文件。"];
		return;
	}
	[self finishWithStatus:0 path:copied];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
		didPickDocumentAtURL:(NSURL *)url {
	[self documentPicker:controller didPickDocumentsAtURLs:@[url]];
}

@end

extern "C" void wolf_ios_present_import_picker(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (g_activePicker) {
			WolfReportError(@"文件选择器已经在打开。");
			return;
		}
		UIViewController *root = WolfRootViewController();
		if (!root) {
			WolfReportError(@"无法获取当前 iOS 视图控制器。");
			return;
		}

		WolfFilePickerDelegate *delegate = [WolfFilePickerDelegate new];
		delegate.mode = WolfFilePickerModeImport;

		UIDocumentPickerViewController *picker = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		picker = [[UIDocumentPickerViewController alloc]
			initWithDocumentTypes:@[ @"public.data", @"public.item" ]
			inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
		picker.delegate = delegate;
		picker.allowsMultipleSelection = NO;
		picker.modalPresentationStyle = UIModalPresentationFormSheet;
		// Set the dismissal delegate before present: if UIKit refuses the
		// presentation, no later completion path will run.
		picker.presentationController.delegate = delegate;

		g_activePicker = delegate;
		[root presentViewController:picker animated:YES completion:^{
			// `presentationController` can be nil before presentation, so set it
			// again once UIKit has created it.
			picker.presentationController.delegate = delegate;
			dispatch_async(dispatch_get_main_queue(), ^{
				// Guard against a transition that silently swallowed the
				// presentation: without this the global picker slot would
				// stay occupied for the rest of the session.
				if (g_activePicker == delegate && root.presentedViewController != picker) {
					[delegate finishWithStatus:2 path:@"无法显示文件选择器，请稍后重试。"];
				}
			});
		}];
	});
}

extern "C" void wolf_ios_present_export_picker(const char *source_path,
		const char *suggested_name) {
	NSString *source = source_path ? [NSString stringWithUTF8String:source_path] : nil;
	NSString *name = suggested_name ? [NSString stringWithUTF8String:suggested_name] : nil;

	dispatch_async(dispatch_get_main_queue(), ^{
		if (g_activePicker) {
			WolfReportError(@"文件选择器已经在打开。");
			return;
		}
		if (!source.length || ![[NSFileManager defaultManager] fileExistsAtPath:source]) {
			WolfReportError(@"找不到待导出的存档备份。");
			return;
		}
		NSString *fileName = name.lastPathComponent;
		if (!fileName.length) {
			fileName = @"ImoutoLife-saves.zip";
		}
		NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
				[NSString stringWithFormat:@"ImoutoLife-export-%@", NSUUID.UUID.UUIDString]];
		NSError *error = nil;
		if (![[NSFileManager defaultManager] createDirectoryAtPath:tempDir
				withIntermediateDirectories:YES
				attributes:nil
				error:&error]) {
			WolfReportError(error.localizedDescription ?: @"无法创建导出临时目录。");
			return;
		}
		NSString *destination = [tempDir stringByAppendingPathComponent:fileName];
		if (![[NSFileManager defaultManager] copyItemAtPath:source
				toPath:destination
				error:&error]) {
			[[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
			WolfReportError(error.localizedDescription ?: @"无法准备导出文件。");
			return;
		}

		UIViewController *root = WolfRootViewController();
		if (!root) {
			[[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
			WolfReportError(@"无法获取当前 iOS 视图控制器。");
			return;
		}

		WolfFilePickerDelegate *delegate = [WolfFilePickerDelegate new];
		delegate.mode = WolfFilePickerModeExport;
		delegate.exportTempDir = tempDir;

		UIDocumentPickerViewController *picker = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		picker = [[UIDocumentPickerViewController alloc]
			initWithURL:[NSURL fileURLWithPath:destination]
			inMode:UIDocumentPickerModeExportToService];
#pragma clang diagnostic pop
		picker.delegate = delegate;
		picker.modalPresentationStyle = UIModalPresentationFormSheet;
		picker.presentationController.delegate = delegate;

		g_activePicker = delegate;
		[root presentViewController:picker animated:YES completion:^{
			picker.presentationController.delegate = delegate;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (g_activePicker == delegate && root.presentedViewController != picker) {
					[delegate finishWithStatus:2 path:@"无法显示文件选择器，请稍后重试。"];
				}
			});
		}];
	});
}
