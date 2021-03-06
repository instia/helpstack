//  HATicketGearImpl.m
//
//Copyright (c) 2014 HelpStack (http://helpstack.io)
//
//Permission is hereby granted, free of charge, to any person obtaining a cop
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//THE SOFTWARE.
#import "HSTicketSource.h"
#import "HSHelpStack.h"

#define CACHE_DIRECTORY_NAME    @"HelpStack"
#define TICKET_CACHE_FILE_NAME  @"HelpApp_Ticket.plist"
#define USER_CACHE_FILE_NAME    @"HelpApp_User.plist"

@interface HSTicketSource ()

@property (nonatomic, strong) NSMutableArray* ticketArray;
@property (nonatomic, strong) NSMutableArray* updateArray;
@property (nonatomic, strong, readwrite) HSGear* gear;
@property (nonatomic, strong, readwrite) HSUser* user;

@end

@implementation HSTicketSource


+ (instancetype)createInstance
{
    HSGear *gear = [[HSHelpStack instance] gear];
    NSAssert (gear != nil, @"No gear was set to HSHelpStack");
    HSTicketSource *source = [[HSTicketSource alloc] initWithGear:gear];
    return source;
}

/**
    Set HAGear, so its method can be called.
 */
- (instancetype)initWithGear:(HSGear *)gear
{
    self = [super init];
    if (self) {
        [self setGear:gear];
        [self initializeTicketFromCache];
    }

    return self;
}

/**
 @warning ticketProtocol in given gear should not be nil.
 */
- (void)initializeTicketFromCache
{
    NSArray *array = [HSTicketSource ticketsAtPath:TICKET_CACHE_FILE_NAME];
    if (array!=nil) {
        self.ticketArray = [NSMutableArray arrayWithArray:array];
    }

    self.user = [HSTicketSource userAtPath:USER_CACHE_FILE_NAME];
}


- (void)registerUserWithFirstName:(NSString *)firstName
                         lastName:(NSString *)lastName
                            email:(NSString *)email
                          success:(void(^)(void))success
                          failure:(void(^)(NSError *error))failure
{
    HSUser *user = [[HSUser alloc] init];
    user.firstName = firstName;
    user.lastName = lastName;
    user.email = email;

    // TODO: may be a check for user info can be performed here.

    [self.gear checkAndFetchValidUser:user withSuccess:^(HSUser *validUser) {
        // Store user info so that it can be used when creating ticket.
        // User info is saved only when first ticket is created successfully.
        self.user = validUser;
        success();


    } failure:^(NSError *e) {
        HALog("searchOrRegisterUser failed: %@",e);
        failure(e);
    }];

}

//////////////////////////////////////////////////

// Store HSUser and check for it while creating a new ticket

- (BOOL)shouldShowUserDetailsFormWhenCreatingTicket
{
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    return (![defaultManager fileExistsAtPath:[HSTicketSource fileCachePath:USER_CACHE_FILE_NAME]]);
}
//////////////////////////////////////////////////

- (void)prepareTicket:(void(^)(void))success
              failure:(void(^)(NSError *))failure
{
    // Checking if gear implements fetchAllTicket:failure:
    if ([self.gear respondsToSelector:@selector(fetchAllTicketForUser:success:failure:)]) {
        [self.gear fetchAllTicketForUser:self.user success:^(NSMutableArray *ticketarray) {
            if (ticketarray != nil) {
                // Ticket fetch was sucess
                self.ticketArray = [NSMutableArray arrayWithArray:ticketarray];
                // Save in cache
                [HSTicketSource saveTickets:self.ticketArray atPath:TICKET_CACHE_FILE_NAME];
            }

            success();
        } failure:^(NSError *e) {
            HALog("Prepare Ticket failed: %@",e);
            failure(e);
        }];
    }
    else {
        // Calling success in order not to break code
        success();
    }
}

- (NSInteger)ticketCount
{
    return [self.ticketArray count];
}

- (HSTicket *)ticketAtPosition:(NSInteger)position
{
    HSTicket *ticket = [self.ticketArray objectAtIndex:position];
    return ticket;
}


- (void)createNewTicket:(HSNewTicket *)details
                success:(void(^)(void))success
                failure:(void(^)(NSError *))failure
{
    // Checking if gear implements createTicket:success:failure:
    if([self.gear respondsToSelector:@selector(createNewTicket:byUser:success:failure:)]) {
        [self.gear createNewTicket:details byUser:self.user success:^(HSTicket *ticket, HSUser* user) {
            // Ticket creation was sucess
            if(ticket!=nil) { // To avoid crash, safe checking
                // Adding new ticket to array at first position
                if(!self.ticketArray) {
                    self.ticketArray = [[NSMutableArray alloc] init];
                }
                [self.ticketArray insertObject:ticket atIndex:0];

                //Saves ticket array in cache and user detail in cache
                [HSTicketSource saveTickets:self.ticketArray atPath:TICKET_CACHE_FILE_NAME];

                if ( user != nil) {
                    self.user = user;
                    [HSTicketSource saveUser:user atPath:USER_CACHE_FILE_NAME];
                }
            }
            success();
        } failure:^(NSError *e) {
            HALog("Create new ticket failed: %@",e);
            failure(e);
        }];
    }
    else {
        success();
    }
}

- (void)prepareUpdate:(HSTicket *)ticketDict
              success:(void(^)(void))success
              failure:(void(^)(NSError *))failure
{
    // Preparing update array for new ticket, dumping array for old ticket
    [self.updateArray removeAllObjects];

    // Checking if gear implements fetchAllUpdate:success:failure:
    if([self.gear respondsToSelector:@selector(fetchAllUpdateForTicket:forUser:success:failure:)]) {
        [self.gear fetchAllUpdateForTicket:ticketDict forUser:self.user success:^(NSMutableArray *updateArray) {
            // Operation was sucess, setting update array
            self.updateArray = updateArray;
            success();
        } failure:^(NSError *e) {
            HALog("Fetch all update failed: %@",e);
            failure(e);
        }];
    }
    else {
        success();
    }
}

- (NSInteger)updateCount
{
    return [self.updateArray count];
}

- (HSUpdate *)updateAtPosition:(NSInteger)position
{
    HSUpdate *update = [self.updateArray objectAtIndex:position];
    return update;
}

- (void)addReply:(HSTicketReply *)details
          ticket:(HSTicket *)ticketDict
         success:(void(^)(void))success
         failure:(void(^)(NSError *))failure
{
    // Checking if gear implements addReply:ticket:success:failure:

    __block NSMutableArray *updates = self.updateArray;

    if([self.gear respondsToSelector:@selector(addReply:forTicket:byUser:success:failure:)]) {
        [self.gear addReply:details forTicket:ticketDict byUser:self.user success:^(HSUpdate *update) {
            if(update!=nil){ // Safe check
                [updates addObject:update];
            }
            success();
        } failure:^(NSError *e) {
            HALog("Add reply to a ticket failed: %@",e);
            failure(e);
        }];
    }
    else {
        success();
    }
}

// Ticket Protocol properties
- (BOOL) isTicketProtocolImplemented
{
    if ([self.gear respondsToSelector:@selector(doLetEmailHandleIssueCreation)]) {
        return ![self.gear doLetEmailHandleIssueCreation];
    }

    return YES;
}

- (NSString *) supportEmailAddress
{
    return self.gear.supportEmailAddress;
}

#pragma mark - Cache functions

+ (void)saveTickets:(NSArray *)tickets
             atPath:(NSString *)fileName
{
    NSString *cacheFilePath = [self fileCachePath:fileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:cacheFilePath]) {
        [fm removeItemAtPath:cacheFilePath error:nil];
    }

    [NSKeyedArchiver archiveRootObject:tickets toFile:cacheFilePath];
}

+ (NSArray *)ticketsAtPath:(NSString *)fileName
{
    NSString *cacheFilePath = [self fileCachePath:fileName];
    return [NSKeyedUnarchiver unarchiveObjectWithFile:cacheFilePath];;
}

+ (void)saveUser:(HSUser *)user
          atPath:(NSString *)fileName
{
    NSString *cacheFilePath = [self fileCachePath:fileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:cacheFilePath]) {
        [fm removeItemAtPath:cacheFilePath error:nil];
    }

    if (user) { // Save only for non nil user
        [NSKeyedArchiver archiveRootObject:user toFile:cacheFilePath];
    }
}

+ (HSUser *)userAtPath:(NSString *)fileName
{
    NSString *cacheFilePath = [self fileCachePath:fileName];
    return [NSKeyedUnarchiver unarchiveObjectWithFile:cacheFilePath];;
}

+ (NSString *)directoryName
{
    return CACHE_DIRECTORY_NAME;
}

+ (NSString *) fileCachePath:(NSString *)fileName
{
    NSString *cacheDirectoryPath = [self getCacheDirectory];
    NSString *cacheFilePath = [cacheDirectoryPath stringByAppendingPathComponent:fileName];
    return cacheFilePath;
}

+ (NSString *) getCacheDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    documentsDirectory = [documentsDirectory stringByAppendingPathComponent:[self directoryName]];

    // Create directory if not already exist
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:&error];

    return documentsDirectory;
}

@end
