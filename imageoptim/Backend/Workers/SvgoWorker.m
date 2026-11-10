
#import "SvgoWorker.h"
#import "../Job.h"
#import "../TempFile.h"
#import "../../log.h"

@implementation SvgoWorker

- (instancetype)initWithLossy:(BOOL)lossy job:(Job *)f {
    if (self = [super initWithFile:f]) {
        useLossy = lossy;
    }
    return self;
}

- (NSInteger)settingsIdentifier {
    return useLossy ? 7 : 8;
}

- (BOOL)optimizeFile:(File *)file toTempPath:(NSURL *)temp {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *scriptPath = [bundle pathForResource:@"svgo" ofType:@"js"];
    if (!scriptPath) {
        IOWarn(@"Broken install, missing script");
        return NO;
    }

    NSArray *args = @[
        scriptPath,
        useLossy ? @"1" : @"0",
        file.path.path,
        temp.path
    ];

    NSString *nodePath = [self nodePath];
    if (!nodePath) {
        IOWarn(@"Node.js 16 or later was not found on PATH or in Homebrew's bin directories");
        return NO;
    }

    [self taskWithPath:nodePath arguments:args];

    [self launchTask];

    BOOL ok = [self waitUntilTaskExit];
    if (!ok) return NO;

    return [job setFileOptimized:[file tempCopyOfPath:temp] toolName:useLossy ? @"SVGO" : @"SVGO lite"];
}

- (NSString *)nodePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *searchPath = [NSProcessInfo processInfo].environment[@"PATH"] ?: @"";
    NSArray<NSString *> *directories = [[searchPath componentsSeparatedByString:@":"] arrayByAddingObjectsFromArray:@[@"/opt/homebrew/bin", @"/usr/local/bin"]];
    for (NSString *directory in directories) {
        if (!directory.isAbsolutePath) continue;
        NSString *candidate = [directory stringByAppendingPathComponent:@"node"];
        if ([fm isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

@end
