//
//  AudioRecorderManager.m
//  AudioRecorderManager
//
//  Created by Joshua Sierles on 15/04/15.
//  Copyright (c) 2015 Joshua Sierles. All rights reserved.
//

#import "AudioRecorderManager.h"
#import "RCTConvert.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import <AVFoundation/AVFoundation.h>

NSString *const AudioRecorderEventProgress = @"recordingProgress";
NSString *const AudioRecorderEventFinished = @"recordingFinished";

@implementation AudioRecorderManager {

  AVAudioRecorder *_audioRecorder;
  AVAudioPlayer *_audioPlayer;

  NSTimeInterval _currentTime;
  id _progressUpdateTimer;
  int _progressUpdateInterval;
  bool permission;
  NSDate *_prevProgressUpdateTime;
  NSURL *_audioFileURL;
  NSNumber *_audioQuality;
  NSNumber *_audioChannels;
  NSNumber *_audioSampleRate;
  AVAudioSession *_recordSession;
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

- (void)sendProgressUpdate {
  if (_audioRecorder && _audioRecorder.recording) {
    _currentTime = _audioRecorder.currentTime;
  } else if (_audioPlayer && _audioPlayer.playing) {
    _currentTime = _audioPlayer.currentTime;
  } else {
    return;
  }

  if (_prevProgressUpdateTime == nil ||
   (([_prevProgressUpdateTime timeIntervalSinceNow] * -1000.0) >= _progressUpdateInterval)) {
      [self.bridge.eventDispatcher sendAppEventWithName:AudioRecorderEventProgress body:@{
      @"currentTime": [NSNumber numberWithFloat:_currentTime]
    }];

    _prevProgressUpdateTime = [NSDate date];
  }
}

- (void)stopProgressTimer {
  [_progressUpdateTimer invalidate];
}

- (void)startProgressTimer {
  _progressUpdateInterval = 250;
  _prevProgressUpdateTime = nil;

  [self stopProgressTimer];

  _progressUpdateTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(sendProgressUpdate)];
  [_progressUpdateTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
  [self.bridge.eventDispatcher sendAppEventWithName:AudioRecorderEventFinished body:@{
      @"status": flag ? @"OK" : @"ERROR",
      @"audioFileURL": [_audioFileURL absoluteString]
    }];
}

- (NSString *) applicationDocumentsDirectory
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
  return basePath;
}

RCT_EXPORT_METHOD(prepareRecordingAtPath:(NSString *)path sampleRate:(float)sampleRate channels:(nonnull NSNumber *)channels quality:(NSString *)quality)
{

  _prevProgressUpdateTime = nil;
  [self stopProgressTimer];

  NSString *audioFilePath = [[self applicationDocumentsDirectory] stringByAppendingPathComponent:path];


  _audioFileURL = [NSURL fileURLWithPath:audioFilePath];

  // Default options

  _audioQuality = [NSNumber numberWithInt:AVAudioQualityHigh];
  _audioChannels = [NSNumber numberWithInt:2];
  _audioSampleRate = [NSNumber numberWithFloat:44100.0];

    // Set audio quality from options
    if (quality != nil) {
      if ([quality  isEqual: @"Low"]) {
        _audioQuality =[NSNumber numberWithInt:AVAudioQualityLow];
      } else if ([quality  isEqual: @"Medium"]) {
        _audioQuality =[NSNumber numberWithInt:AVAudioQualityMedium];
      } else if ([quality  isEqual: @"High"]) {
        _audioQuality =[NSNumber numberWithInt:AVAudioQualityHigh];
      }
    }

    // Set channels from options
    if (channels != nil) {
      _audioChannels = channels;
    }

    // Set sample rate from options
    _audioSampleRate = [NSNumber numberWithFloat:sampleRate];



  /*NSDictionary *recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:
          _audioQuality, AVEncoderAudioQualityKey,
          [NSNumber numberWithInt:16], AVEncoderBitRateKey,
          _audioChannels, AVNumberOfChannelsKey,
          _audioSampleRate, AVSampleRateKey,
          nil];

  NSDictionary *recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                  [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                                  [NSNumber numberWithInt:128000], AVEncoderBitRateKey,
                                  [NSNumber numberWithInt: 1], AVNumberOfChannelsKey,
                                  [NSNumber numberWithInt:AVAudioQualityMedium], AVEncoderAudioQualityKey,
                                  nil];*/

  NSDictionary *recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                  [NSNumber numberWithFloat:22050.0], AVSampleRateKey,
                                  [NSNumber numberWithInt: 1], AVNumberOfChannelsKey,
                                  [NSNumber numberWithInt:AVAudioQualityHigh], AVEncoderAudioQualityKey,
                                  nil];


  NSError *error = nil;

  _recordSession = [AVAudioSession sharedInstance];

  

  [_recordSession setCategory:AVAudioSessionCategoryMultiRoute error:nil];

  _audioRecorder = [[AVAudioRecorder alloc]
                initWithURL:_audioFileURL
                settings:recordSettings
                error:&error];

  _audioRecorder.delegate = self;

  if (error) {
      NSLog(@"error: %@", [error localizedDescription]);
      // TODO: dispatch error over the bridge
    } else {
      [_audioRecorder prepareToRecord];
  }
}

RCT_EXPORT_METHOD(startRecording)
{
  if (!_audioRecorder.recording) {
    [self startProgressTimer];
    [_recordSession setActive:YES error:nil];
    [_audioRecorder record];

  }
}

RCT_EXPORT_METHOD(gotoSettings)
{
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}


RCT_EXPORT_METHOD(checkPermission:(RCTResponseSenderBlock)callback)
{
  [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
    if (granted) {
      NSLog(@"Granted");
      callback(@[[NSNull null],  @1]);
    } else {
      NSLog(@"denied");
      callback(@[[NSNull null],  @0]);
    }
  }];
  
  
}


RCT_EXPORT_METHOD(stopRecording)
{
  if (_audioRecorder.recording) {
    [_audioRecorder stop];
    [_recordSession setActive:NO error:nil];
    _prevProgressUpdateTime = nil;
  }
}

RCT_EXPORT_METHOD(pauseRecording)
{
  if (_audioRecorder.recording) {
    [self stopProgressTimer];
    [_audioRecorder pause];
  }
}

RCT_EXPORT_METHOD(playRecording)
{
  if (_audioRecorder.recording) {
    NSLog(@"stop the recording before playing");
    return;

  } else {

    NSError *error;

    if (!_audioPlayer.playing) {
      _audioPlayer = [[AVAudioPlayer alloc]
        initWithContentsOfURL:_audioRecorder.url
        error:&error];

      if (error) {
        [self stopProgressTimer];
        NSLog(@"audio playback loading error: %@", [error localizedDescription]);
        // TODO: dispatch error over the bridge
      } else {
        [self startProgressTimer];
        [_audioPlayer play];
      }
    }
  }
}

RCT_EXPORT_METHOD(pausePlaying)
{
  if (_audioPlayer.playing) {
    [_audioPlayer pause];
  }
}

RCT_EXPORT_METHOD(stopPlaying)
{
  if (_audioPlayer.playing) {
    [_audioPlayer stop];
  }
}

@end
