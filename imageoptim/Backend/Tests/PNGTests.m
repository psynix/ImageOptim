@import Cocoa;
@import ImageIO;
#import <XCTest/XCTest.h>
#import "Job.h"
#import "JobQueue.h"
#import "File.h"

@interface PNGTests : XCTestCase
@end

@implementation PNGTests

- (void)testOxiPNGPreservesPixelsAtEveryEffortLevel {
    NSData *original = [self pngWithMetadata];
    for (NSNumber *level in @[@2, @4, @6]) {
        NSData *optimized = [self optimize:original level:level.integerValue strip:NO];
        XCTAssertLessThan(optimized.length, original.length);
        XCTAssertEqualObjects([self renderedPixels:optimized], [self renderedPixels:original]);
    }
}

- (void)testOxiPNGHonoursMetadataPreference {
    NSData *original = [self pngWithMetadata];
    NSString *description = @"ImageOptim PNG metadata regression";
    XCTAssertEqualObjects([self pngProperties:original][(NSString *)kCGImagePropertyPNGDescription], description);
    NSData *preserved = [self optimize:original level:4 strip:NO];
    NSData *stripped = [self optimize:original level:4 strip:YES];
    XCTAssertEqualObjects([self pngProperties:preserved][(NSString *)kCGImagePropertyPNGDescription], description);
    XCTAssertNil([self pngProperties:stripped][(NSString *)kCGImagePropertyPNGDescription]);
    XCTAssertEqualObjects([self renderedPixels:preserved], [self renderedPixels:original]);
    XCTAssertEqualObjects([self renderedPixels:stripped], [self renderedPixels:original]);
    for (NSData *data in @[preserved, stripped]) {
        XCTAssertEqualObjects([self colorSpaceName:data], (__bridge NSString *)kCGColorSpaceDisplayP3);
    }
}

- (void)testTruncatedPNGIsNotReplacedWithPartialOutput {
    NSData *original = [self pngWithMetadata];
    NSData *truncated = [original subdataWithRange:NSMakeRange(0, original.length / 2)];
    XCTAssertEqualObjects([self optimize:truncated level:4 strip:YES], truncated);
}

- (void)testRGBProfileIsPreservedForGrayscalePixels {
    NSData *original = [self pngWithMetadataGrayscale:YES];
    NSData *optimized = [self optimize:original level:4 strip:NO];
    XCTAssertEqualObjects([self colorSpaceName:optimized], [self colorSpaceName:original]);
    XCTAssertEqualObjects([self renderedPixels:optimized], [self renderedPixels:original]);
}

- (NSData *)optimize:(NSData *)original level:(NSInteger)level strip:(BOOL)strip {
    NSURL *path = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSUUID UUID].UUIDString];
    [defaults registerDefaults:@{
        @"OptiPngEnabled": @YES, @"AdvPngLevel": @(level), @"PngOutRemoveChunks": @(strip),
        @"PngCrush2Enabled": @NO, @"PngOutEnabled": @NO, @"ZopfliEnabled": @NO,
        @"AdvPngEnabled": @NO, @"LossyEnabled": @NO
    }];
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    JobQueue *queue = [[JobQueue alloc] initWithCPUs:2 dirs:1 files:1 defaults:defaults];
    [queue addJob:job];
    [queue wait];
    XCTAssertTrue(job.isDone);
    XCTAssertFalse(job.isBusy);
    NSData *result = [NSData dataWithContentsOfURL:path];
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
    if (job.revertFile) [[NSFileManager defaultManager] removeItemAtURL:job.revertFile.path error:nil];
    return result;
}

- (NSData *)pngWithMetadata {
    return [self pngWithMetadataGrayscale:NO];
}

- (NSData *)pngWithMetadataGrayscale:(BOOL)grayscale {
    enum { width = 17, height = 13 };
    uint16_t pixels[width * height * 4];
    for (size_t index = 0; index < width * height; index++) {
        pixels[4 * index] = (uint16_t)(index * 251);
        pixels[4 * index + 1] = (uint16_t)(index * (grayscale ? 251 : 173));
        pixels[4 * index + 2] = (uint16_t)(index * (grayscale ? 251 : 97));
        pixels[4 * index + 3] = UINT16_MAX;
    }
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 16, width * 8, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder16Host);
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)@{
        (NSString *)kCGImagePropertyPNGDictionary: @{(NSString *)kCGImagePropertyPNGDescription: @"ImageOptim PNG metadata regression"}
    });
    XCTAssertTrue(CGImageDestinationFinalize(destination));
    CFRelease(destination);
    CGImageRelease(image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

- (NSDictionary *)pngProperties:(NSData *)data {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return properties[(NSString *)kCGImagePropertyPNGDictionary];
}

- (NSString *)colorSpaceName:(NSData *)data {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    XCTAssertNotEqual(image, NULL);
    NSString *name = image ? CFBridgingRelease(CGColorSpaceCopyName(CGImageGetColorSpace(image))) : nil;
    if (image) CGImageRelease(image);
    CFRelease(source);
    return name;
}

- (NSData *)renderedPixels:(NSData *)data {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    XCTAssertNotEqual(image, NULL);
    if (!image) { CFRelease(source); return nil; }
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 8];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 16, width * 8, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder16Host);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    CGImageRelease(image);
    CFRelease(source);
    return pixels;
}

@end
