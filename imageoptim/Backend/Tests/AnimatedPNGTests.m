@import Cocoa;
@import ImageIO;
#import <XCTest/XCTest.h>
#import "File.h"
#import "TempFile.h"
#import "Job.h"
#import "JobQueue.h"

@interface AnimatedPNGTests : XCTestCase
@end

@implementation AnimatedPNGTests

- (void)testAnimatedPNGPreservesFramesAndTimingWithAllToolsEnabled {
    NSData *original = [self animationData];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    JobQueue *queue = [[JobQueue alloc] initWithCPUs:4 dirs:1 files:1 defaults:[self defaultsWithOxiPNG:YES]];
    [queue addJob:job];
    [queue wait];

    NSData *optimized = [NSData dataWithContentsOfURL:path];
    XCTAssertTrue(job.isDone);
    XCTAssertFalse(job.isFailed);
    XCTAssertLessThan(optimized.length, original.length);
    XCTAssertEqualObjects([self animationChunks:optimized], [self animationChunks:original]);

    CGImageSourceRef before = CGImageSourceCreateWithData((__bridge CFDataRef)original, NULL);
    CGImageSourceRef after = CGImageSourceCreateWithData((__bridge CFDataRef)optimized, NULL);
    XCTAssertNotEqual(before, NULL);
    XCTAssertNotEqual(after, NULL);
    if (before && after) {
        XCTAssertEqual(CGImageSourceGetCount(before), 2u);
        XCTAssertEqual(CGImageSourceGetCount(after), 2u);
        for (size_t index = 0; index < 2; index++) {
            XCTAssertEqualObjects([self pixelsAtIndex:index source:before], [self pixelsAtIndex:index source:after]);
        }
    }
    if (before) CFRelease(before);
    if (after) CFRelease(after);
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
    if (job.revertFile) [[NSFileManager defaultManager] removeItemAtURL:job.revertFile.path error:nil];
}

- (void)testAnimatedPNGRemainsUntouchedWhenOxiPNGIsDisabled {
    NSData *original = [self animationData];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    JobQueue *queue = [[JobQueue alloc] initWithCPUs:4 dirs:1 files:1 defaults:[self defaultsWithOxiPNG:NO]];
    [queue addJob:job];
    [queue wait];
    XCTAssertTrue(job.isDone);
    XCTAssertTrue(job.isFailed);
    XCTAssertFalse(job.isBusy);
    XCTAssertTrue([job.statusText containsString:@"OxiPNG"]);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:path], original);
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
}

- (void)testAnimationDetectionSurvivesFileCopies {
    NSData *data = [self animationData];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([data writeToURL:path atomically:YES]);
    File *file = [[File alloc] initWithData:data fromPath:path];
    XCTAssertTrue(file.isAnimatedPNG);
    NSArray<File *> *copies = @[[file copyOfPath:path], [file copyOfPath:path size:data.length],
                               [file tempCopyOfPath:path], [file tempCopyOfPath:path size:data.length]];
    for (File *copy in copies) XCTAssertTrue(copy.isAnimatedPNG);
}

- (void)testChunkDetectionIgnoresTextAndHandlesTruncatedChunks {
    NSMutableData *data = [[self animationData] mutableCopy];
    // A chunk name inside text must not be mistaken for an animation chunk.
    NSRange control = [data rangeOfData:[@"acTL" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, data.length)];
    [data replaceBytesInRange:control withBytes:"tEXt"];
    NSRange text = [data rangeOfData:[@"animation" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, data.length)];
    [data replaceBytesInRange:NSMakeRange(text.location, 4) withBytes:"acTL"];
    File *staticPNG = [[File alloc] initWithData:data fromPath:[self temporaryURL]];
    XCTAssertFalse(staticPNG.isAnimatedPNG);

    const unsigned char truncated[] = {0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0xff,0xff,0xff,0xff,'t','E','X','t',0,0,0,0};
    File *malformed = [[File alloc] initWithData:[NSData dataWithBytes:truncated length:sizeof(truncated)] fromPath:[self temporaryURL]];
    XCTAssertFalse(malformed.isAnimatedPNG);
    for (NSUInteger length = 6; length < sizeof(truncated); length++) {
        XCTAssertNotNil([[File alloc] initWithData:[NSData dataWithBytes:truncated length:length] fromPath:[self temporaryURL]]);
    }
}

- (NSURL *)temporaryURL {
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
}

- (NSUserDefaults *)defaultsWithOxiPNG:(BOOL)enabled {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSUUID UUID].UUIDString];
    [defaults registerDefaults:@{
        @"OptiPngEnabled": @(enabled), @"PngCrush2Enabled": @YES, @"PngOutEnabled": @YES,
        @"ZopfliEnabled": @YES, @"AdvPngEnabled": @YES, @"PngOutRemoveChunks": @YES,
        @"LossyEnabled": @YES, @"PngMinQuality": @80, @"AdvPngLevel": @2,
        @"PreservePermissions": @NO
    }];
    return defaults;
}

- (NSArray<NSData *> *)animationChunks:(NSData *)data {
    NSMutableArray *chunks = [NSMutableArray new];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger offset = 8; data.length >= offset + 12;) {
        uint32_t length;
        memcpy(&length, bytes + offset, sizeof(length));
        length = CFSwapInt32BigToHost(length);
        if (length > data.length - offset - 12) break;
        if (memcmp(bytes + offset + 4, "acTL", 4) == 0 || memcmp(bytes + offset + 4, "fcTL", 4) == 0) {
            [chunks addObject:[data subdataWithRange:NSMakeRange(offset + 4, length + 4)]];
        }
        offset += length + 12;
    }
    return chunks;
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

- (NSData *)animationData {
    // Two opaque 8x8 frames, delays 1/10 and 7/100 seconds, three loops, uncompressed zlib and removable text.
    return [[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAABFXRFWHRDb21tZW50AGFuaW1hdGlvbiByZWdyZXNzaW9uIGZpeHR1cmUgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgcGFkZGluZyBwYWRkaW5nIHBhZGRpbmcgE7FARAAAAAhhY1RMAAAAAgAAAANqhMLKAAAAGmZjVEwAAAAAAAAACAAAAAgAAAAAAAAAAAABAAoAAPJOumIAAAETSURBVHgBAQgB9/4A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP8A/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP/C13+BasU6cgAAABpmY1RMAAAAAQAAAAgAAAAIAAAAAAAAAAAABwBkAACkNEM8AAABF2ZkQVQAAAACeAEBCAH3/gAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAAAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//0NXf4Ff/U0pAAAAAElFTkSuQmCC" options:0];
}

@end
