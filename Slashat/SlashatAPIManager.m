//
//  SlashatAPIManager.m
//  Slashat
//
//  Created by Johan Larsson on 2013-08-31.
//  Copyright (c) 2013 Johan Larsson. All rights reserved.
//

#import "SlashatAPIManager.h"
#import "AFJSONRequestOperation.h"
#import "RSSParser.h"
#import "APIKey.h"
#import "SlashatHost.h"
#import "SlashatCalendarItem.h"
#import "DateUtils.h"
#import "SlashatHighFiveUser.h"
#import <Security/Security.h>
#import "KDJKeychainItemWrapper.h"

@interface SlashatAPIManager ()

@property (strong, nonatomic) NSString *highFiveAuthToken;
@property (strong, nonatomic) KDJKeychainItemWrapper *tokenKeyChainItem;

@end

@implementation SlashatAPIManager

+ (SlashatAPIManager *)sharedClient {
    static SlashatAPIManager *_sharedClient = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedClient = [[SlashatAPIManager alloc] init];
    });
    
    return _sharedClient;
}

- (void)fetchArchiveEpisodesWithSuccess:(void (^)(NSArray *episodes))success failure:(void (^)(NSError *error))failure
{
    NSLog(@"SlashatAPIManager: Fetching archive episodes");
    NSURL *url = [NSURL URLWithString:@"http://slashat.se/feed/podcast/slashat.xml"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [RSSParser parseRSSFeedForRequest:request success:success failure:failure];
}

- (void)fetchLiveBroadcastIdWithSuccess:(void (^)(NSString *broadcastId))success failure:(void (^)(NSError *error))failure
{
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://api.bambuser.com/broadcast.json"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    NSString *userName = self.useDevValues ? @"slashat_dev" : @"slashat";
    NSString *apiKey = self.useDevValues ? BAMBUSER_DEV_API_KEY : BAMBUSER_TRANSCODE_API_KEY;
    
    NSLog(@"Fetching live broadcastId for user %@", userName);
    
    NSString *postParams = [NSString stringWithFormat:@"username=%@&type=live&limit=1&api_key=%@", userName, apiKey];
    [request setHTTPBody:[postParams dataUsingEncoding:NSUTF8StringEncoding]];
    
    AFJSONRequestOperation *operation = [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        
        NSArray *broadcasts = [JSON valueForKeyPath:@"result"];
        
        if (broadcasts.count > 0) {
            NSString *broadcastId = [(id)[broadcasts objectAtIndex:0] valueForKeyPath:@"vid"];
            success(broadcastId);
        } else {
            success(nil);
        }
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }];
    
    [operation start];
}

- (void)fetchLiveStreamUrlForBroadcastId:(NSString *)broadcastId sucess:(void(^)(NSURL *streamUrl))success failure:(void (^)(NSError *error))failure
{
    NSURL *broadcastUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@.json", BAMBUSER_TRANSCODE_URL, broadcastId]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:broadcastUrl];
    [request setHTTPMethod:@"POST"];
    
    NSString *postParams = [NSString stringWithFormat:@"api_key=%@&preset=hls", BAMBUSER_TRANSCODE_API_KEY];
    [request setHTTPBody:[postParams dataUsingEncoding:NSUTF8StringEncoding]];
    
    AFJSONRequestOperation *operation = [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        
        NSURL *streamUrl = [NSURL URLWithString:[[JSON valueForKeyPath:@"result"] valueForKeyPath:@"url"]];
        success(streamUrl);
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"SlashatAPIManager: fetchLiveStreamUrlForBroadcastId: error: %@", error);
        failure(error);
    }];
    
    [operation start];
}


- (void)fetchNextSlashatCalendarItemWithSuccess:(void(^)(SlashatCalendarItem *calendarItem))success failure:(void(^)(NSError *error))failure
{
    NSString *parameterString = [NSString stringWithFormat:@"orderBy=startTime&singleEvents=true&timeMin=%@&key=%@", [DateUtils convertNSDateToGoogleCalendarString:[NSDate date]], GOOGLE_CALENDAR_API_KEY];
    
    NSString *encodedParameterString = (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,(CFStringRef)parameterString, NULL, CFSTR("+:"), kCFStringEncodingUTF8);
    
    NSString *calendarUrlString = [NSString stringWithFormat:@"https://www.googleapis.com/calendar/v3/calendars/3om4bg9o7rdij1vuo7of48n910@group.calendar.google.com/events?%@", encodedParameterString];
    
    NSURL *calendarUrl = [NSURL URLWithString:calendarUrlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:calendarUrl];
    [request setHTTPMethod:@"GET"];
    
    AFJSONRequestOperation *operation = [AFJSONRequestOperation JSONRequestOperationWithRequest:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        
        NSString *dateString = [[[(NSArray *)[JSON valueForKeyPath:@"items"] objectAtIndex:0] valueForKeyPath:@"start"] valueForKeyPath:@"dateTime"];
        
        SlashatCalendarItem *calendarItem = [[SlashatCalendarItem alloc] init];
        calendarItem.title = [[(NSArray *)[JSON valueForKeyPath:@"items"] objectAtIndex:0] valueForKeyPath:@"summary"];
        calendarItem.date = [DateUtils createNSDateFrom:dateString];
        
        success(calendarItem);
        
    } failure:^(NSURLRequest *request , NSURLResponse *response , NSError *error , id JSON){
        NSLog(@"Failed: %@",[error localizedDescription]);
    }];
    
    [operation start];
}

- (NSArray *)getSlashatHostsInSections
{
    NSString *plistHostPath = [[NSBundle mainBundle] pathForResource:@"Slashat-hosts" ofType:@"plist"];
    NSArray *plistRootArray = [[NSArray alloc] initWithContentsOfFile:plistHostPath];
    
    NSMutableArray *hostSections = [[NSMutableArray alloc] init];
    
    for (int i=0; i < plistRootArray.count; i++) {
        
        NSArray *sectionHosts = [plistRootArray objectAtIndex:i][@"items"];
        
        NSMutableArray *hosts = [[NSMutableArray alloc] init];
        
        for (int j=0; j<sectionHosts.count; j++) {
            SlashatHost *host = [[SlashatHost alloc] init];
            host.name = [sectionHosts objectAtIndex:j][@"name"];
            host.profileImage = [UIImage imageNamed:[sectionHosts objectAtIndex:j][@"image"]];
            host.shortDescription = [sectionHosts objectAtIndex:j][@"short_description"];
            host.longDescription = [sectionHosts objectAtIndex:j][@"long_description"];
            host.twitterHandle = [sectionHosts objectAtIndex:j][@"twitter"];
            host.emailAdress = [sectionHosts objectAtIndex:j][@"mail"];
            host.link = [NSURL URLWithString:[sectionHosts objectAtIndex:j][@"web"]];
            [hosts addObject:host];
        }
        
        [hostSections addObject:hosts];
    }
    
    return hostSections;
}

- (NSArray *)getHostSectionTitles
{
    NSString *plistHostPath = [[NSBundle mainBundle] pathForResource:@"Slashat-hosts" ofType:@"plist"];
    NSArray *plistRootArray = [[NSArray alloc] initWithContentsOfFile:plistHostPath];
    
    NSMutableArray *sectionTitles = [[NSMutableArray alloc] init];
    for (int i = 0; i < plistRootArray.count; i++) {
        NSString *sectionTitle = [plistRootArray objectAtIndex:i][@"title"];
        [sectionTitles addObject:sectionTitle];
    }
    
    return sectionTitles;
}

- (void)loginHighFiveUserWithCredentials:(NSString *)userName password:(NSString *)password success:(void(^)(NSString *authToken))success failure:(void(^)(NSError *error))failure
{
    self.highFiveAuthToken = @"test_token";
    NSLog(@"SlashatAPIManager: loginHighFiveUserWithCredentials: token: %@", [self.tokenKeyChainItem objectForKey:(__bridge id)(kSecValueData)]);
    success(self.highFiveAuthToken);
}

- (void)fetchSlashatHighFiveUserWithSuccess:(void(^)(SlashatHighFiveUser *user))success failure:(void(^)(NSError *error))failure
{
    SlashatHighFiveUser *user = [[SlashatHighFiveUser alloc] init];
    user.userName = @"kottkrig";
    user.qrCode = [NSURL URLWithString:@"http://api.qrserver.com/v1/create-qr-code/?data=Slashat%20rules&size=510x510"];
    user.profilePicture = [NSURL URLWithString:@"http://www.gravatar.com/avatar/a85e891db7a0bfd5e3ec12575559bece.png"];
    
    user.highFivers = [self getMockHighFiveUsers];
    success(user);
}

- (void)fetchAllSlashatHighFiversWithSuccess:(void(^)(NSArray *users))success failure:(void(^)(NSError *error))failure
{
    success([self getMockHighFiveUsers]);
}

- (NSArray *)getMockHighFiveUsers
{
    SlashatHighFiveUser *highFiver1 = [[SlashatHighFiveUser alloc] init];
    highFiver1.userName = @"jezper";
    highFiver1.profilePicture = [NSURL URLWithString:@"http://forum.slashat.se/download/file.php?avatar=54_1371413866.png"];
    
    SlashatHighFiveUser *highFiver2 = [[SlashatHighFiveUser alloc] init];
    highFiver2.userName = @"tommie";
    highFiver2.profilePicture = [NSURL URLWithString:@"http://forum.slashat.se/download/file.php?avatar=53_1379446237.png"];
    
    SlashatHighFiveUser *highFiver3 = [[SlashatHighFiveUser alloc] init];
    highFiver3.userName = @"jonasson";
    highFiver3.profilePicture = [NSURL URLWithString:@"http://forum.slashat.se/download/file.php?avatar=66_1368392108.jpg"];
    
    SlashatHighFiveUser *highFiver4 = [[SlashatHighFiveUser alloc] init];
    highFiver4.userName = @"smiley";
    highFiver4.profilePicture = [NSURL URLWithString:@"http://forum.slashat.se/download/file.php?avatar=1197_1372799107.jpg"];
    
    return @[highFiver1, highFiver2, highFiver3, highFiver4];
}

- (void)setHighFiveAuthToken:(NSString *)authToken
{
    _highFiveAuthToken = authToken;
    
    if (!self.tokenKeyChainItem) {
        self.tokenKeyChainItem = [[KDJKeychainItemWrapper alloc] initWithIdentifier:@"HighFiveToken" accessGroup:nil];
    }
    
    [self.tokenKeyChainItem setObject:authToken forKey:(__bridge id)kSecValueData];
}

- (NSString *)getTokenFromKeyChain
{
    if (!self.tokenKeyChainItem) {
        self.tokenKeyChainItem = [[KDJKeychainItemWrapper alloc] initWithIdentifier:@"HighFiveToken" accessGroup:nil];
    }
    
    return (NSString *)[self.tokenKeyChainItem objectForKey:(__bridge id)kSecValueData];
}

- (BOOL)userIsLoggedIn
{
    NSString *token = [self getTokenFromKeyChain];
    return token != nil;
}

@end
