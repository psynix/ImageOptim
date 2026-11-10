@import Cocoa;
@import ImageIO;
#import <XCTest/XCTest.h>
#import "Job.h"
#import "JobQueue.h"
#import "File.h"

@interface JPEGTests : XCTestCase
@end

@implementation JPEGTests

- (void)testLosslessJPEGPreservesPixelsAndOptionalMetadata {
    NSData *original = [self fixture];
    for (NSNumber *strip in @[@NO, @YES]) {
        NSURL *path = [self temporaryURL];
        XCTAssertTrue([original writeToURL:path atomically:YES]);
        NSUserDefaults *defaults = [self defaults];
        [defaults setBool:strip.boolValue forKey:@"JpegTranStripAll"];
        Job *job = [self optimize:path defaults:defaults];
        NSData *optimized = [NSData dataWithContentsOfURL:path];

        XCTAssertTrue(job.isDone);
        XCTAssertFalse(job.isFailed);
        XCTAssertLessThan(optimized.length, original.length);
        XCTAssertEqualObjects([self pixels:original], [self pixels:optimized]);
        for (NSData *metadata in [self metadata]) {
            NSRange marker = [optimized rangeOfData:metadata options:0 range:NSMakeRange(0, optimized.length)];
            XCTAssertEqual(marker.location != NSNotFound, !strip.boolValue);
        }
        [self removeOutput:path job:job];
    }
}

- (void)testLossyJPEGOptimOutputSizeParsing {
    NSData *original = [self fixture];
    NSURL *path = [self temporaryURL];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:YES forKey:@"LossyEnabled"];
    [defaults setBool:NO forKey:@"JpegTranEnabled"];
    [defaults setInteger:80 forKey:@"JpegOptimMaxQuality"];
    Job *job = [self optimize:path defaults:defaults];
    NSData *optimized = [NSData dataWithContentsOfURL:path];

    XCTAssertTrue(job.isDone);
    XCTAssertFalse(job.isFailed);
    XCTAssertLessThan(optimized.length, original.length * 0.95);
    XCTAssertEqual(job.byteSizeOptimized.unsignedIntegerValue, optimized.length);
    XCTAssertNotNil([self pixels:optimized]);
    [self removeOutput:path job:job];
}

- (Job *)optimize:(NSURL *)path defaults:(NSUserDefaults *)defaults {
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    JobQueue *queue = [[JobQueue alloc] initWithCPUs:2 dirs:1 files:1 defaults:defaults];
    [queue addJob:job];
    [queue wait];
    return job;
}

- (NSUserDefaults *)defaults {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSUUID UUID].UUIDString];
    [defaults registerDefaults:@{@"JpegOptimEnabled": @YES, @"JpegTranEnabled": @YES,
                                @"LossyEnabled": @NO, @"PreservePermissions": @NO}];
    return defaults;
}

- (NSURL *)temporaryURL {
    return [NSURL fileURLWithPath:[[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:@"jpg"]];
}

- (NSData *)fixture {
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:64 pixelsHigh:64 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 64; y++) {
        for (NSInteger x = 0; x < 64; x++) {
            [image setColor:[NSColor colorWithRed:(x % 8) / 7.0 green:(y % 8) / 7.0 blue:0.5 alpha:1] atX:x y:y];
        }
    }
    NSData *jpeg = [image representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.95}];
    NSMutableData *fixture = [NSMutableData dataWithData:[jpeg subdataWithRange:NSMakeRange(0, 2)]];
    NSUInteger index = 0;
    const unsigned char types[] = {0xfe, 0xe1, 0xe2};
    for (NSData *metadata in [self metadata]) {
        const unsigned char header[] = {0xff, types[index++]};
        uint16_t length = CFSwapInt16HostToBig((uint16_t)metadata.length + 2);
        [fixture appendBytes:header length:sizeof(header)];
        [fixture appendBytes:&length length:sizeof(length)];
        [fixture appendData:metadata];
    }
    [fixture appendData:[jpeg subdataWithRange:NSMakeRange(2, jpeg.length - 2)]];
    return fixture;
}

- (NSArray<NSData *> *)metadata {
    const unsigned char exif[] = {'E','x','i','f',0,0,'I','I',42,0,8,0,0,0,1,0,0x12,1,3,0,1,0,0,0,1,0,0,0,0,0,0,0};
    const unsigned char profileHeader[] = {'I','C','C','_','P','R','O','F','I','L','E',0,1,1};
    NSMutableData *profile = [NSMutableData dataWithBytes:profileHeader length:sizeof(profileHeader)];
    [profile appendData:[NSColorSpace sRGBColorSpace].ICCProfileData];
    return @[[ @"ImageOptim JPEG regression metadata" dataUsingEncoding:NSASCIIStringEncoding],
             [NSData dataWithBytes:exif length:sizeof(exif)], profile];
}

- (NSData *)pixels:(NSData *)data {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    XCTAssertNotEqual(source, NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
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

- (void)removeOutput:(NSURL *)path job:(Job *)job {
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
    if (job.revertFile) [[NSFileManager defaultManager] removeItemAtURL:job.revertFile.path error:nil];
}

@end
