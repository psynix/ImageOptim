@import Cocoa;
@import ImageIO;
#import <XCTest/XCTest.h>
#import "Job.h"
#import "JobQueue.h"
#import "File.h"

@interface GIFTests : XCTestCase
@end

@implementation GIFTests

- (void)testGIFPreservesFramePixelsDisposalTimingAndLoopCount {
    // Upstream's disposal regression, with a finite Netscape loop extension.
    NSData *fixture = [[NSData alloc] initWithBase64EncodedString:@"R0lGODlhKAAUAPEAAP/////TAP8AAAAAACH5BAEUAAAALAAAAAAoABQAAAIahI+py+0Po5y02ouz3rz7D4biSJbmiabqihUAIfkEARQAAAAsAAAAACgAFAAAAiiEj6nL7Q+jnLTai7PevPu/BeIYgAiJmgaamiypvmMsl25Ny/m7t2YBACH5BAkUAAAALAAAAAAoABQAAAIohI+py+0Po5y02ouz3rz7vwniKIAIiZoGmposqb5jLJduTcv5u7dmAQAh+QQBFAAAACwAAAAAKAAUAAACGoSPqcvtD6OctNqLs968+w+G4kiW5omm6ooVADs=" options:0];
    const unsigned char loop[] = {0x21,0xff,0x0b,'N','E','T','S','C','A','P','E','2','.','0',3,1,7,0,0};
    NSMutableData *original = [fixture mutableCopy];
    [original replaceBytesInRange:NSMakeRange(25, 0) withBytes:loop length:sizeof(loop)];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    Job *job = [self optimizeURL:path];
    NSData *optimized = [NSData dataWithContentsOfURL:path];
    XCTAssertTrue(job.isDone);
    XCTAssertFalse(job.isFailed);
    XCTAssertLessThan(optimized.length, original.length);

    CGImageSourceRef before = CGImageSourceCreateWithData((__bridge CFDataRef)original, NULL);
    CGImageSourceRef after = CGImageSourceCreateWithData((__bridge CFDataRef)optimized, NULL);
    XCTAssertNotEqual(before, NULL);
    XCTAssertNotEqual(after, NULL);
    if (before && after) {
        XCTAssertEqual(CGImageSourceGetCount(before), 4u);
        XCTAssertEqual(CGImageSourceGetCount(after), 4u);
        NSDictionary *beforeProperties = CFBridgingRelease(CGImageSourceCopyProperties(before, NULL));
        NSDictionary *afterProperties = CFBridgingRelease(CGImageSourceCopyProperties(after, NULL));
        // ImageIO includes the first cycle in addition to the seven requested repeats.
        XCTAssertEqualObjects(beforeProperties[(id)kCGImagePropertyGIFDictionary][(id)kCGImagePropertyGIFLoopCount], @8);
        XCTAssertEqualObjects(beforeProperties[(id)kCGImagePropertyGIFDictionary][(id)kCGImagePropertyGIFLoopCount], afterProperties[(id)kCGImagePropertyGIFDictionary][(id)kCGImagePropertyGIFLoopCount]);
        for (size_t index = 0; index < 4; index++) {
            XCTAssertEqualObjects([self pixelsAtIndex:index source:before], [self pixelsAtIndex:index source:after]);
            NSDictionary *a = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(before, index, NULL));
            NSDictionary *b = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(after, index, NULL));
            XCTAssertEqualObjects(a[(id)kCGImagePropertyGIFDictionary][(id)kCGImagePropertyGIFUnclampedDelayTime], b[(id)kCGImagePropertyGIFDictionary][(id)kCGImagePropertyGIFUnclampedDelayTime]);
        }
    }
    if (before) CFRelease(before);
    if (after) CFRelease(after);
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
    if (job.revertFile) [[NSFileManager defaultManager] removeItemAtURL:job.revertFile.path error:nil];
}

- (void)testTruncatedGIFRemainsUntouched {
    // Gifsicle's default error recovery emits a smaller partial animation for this input.
    NSData *original = [[NSData alloc] initWithBase64EncodedString:@"R0lGODlhAgACAPEAAAAAAP////8AAAD/ACH/C05FVFNDQVBFMi4wAwEFAAAh/gVoZWxsbwAh+QQECgD/ACwAAAAAAgACAAACA0QEBQAh+QQECgD/ACwAAAAAAgACAA==" options:0];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    [self optimizeURL:path];
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:path], original);
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
}

- (Job *)optimizeURL:(NSURL *)path {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSUUID UUID].UUIDString];
    [defaults registerDefaults:@{@"GifsicleEnabled": @YES, @"GifQuality": @100, @"AdvPngLevel": @4, @"PreservePermissions": @NO}];
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    JobQueue *queue = [[JobQueue alloc] initWithCPUs:2 dirs:1 files:1 defaults:defaults];
    [queue addJob:job];
    [queue wait];
    return job;
}

- (NSURL *)temporaryURL {
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"gif"]]];
}

- (NSData *)pixelsAtIndex:(size_t)index source:(CGImageSourceRef)source {
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, index, NULL);
    XCTAssertNotEqual(image, NULL);
    if (!image) return nil;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    XCTAssertNotEqual(context, NULL);
    if (context) {
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(space);
    CGImageRelease(image);
    return pixels;
}

@end
