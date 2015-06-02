//
//  TD_DatabaseBlobFilenamesTests.m
//  Tests
//
//  Created by Enrique de la Torre Fernandez on 29/05/2015.
//
//

#import <XCTest/XCTest.h>

#import <FMDB.h>

#import "TD_Database+BlobFilenames.h"

#import "CDTEncryptionKeyNilProvider.h"

#define TDDATABASEBLOBFILENAMESTESTS_DBFILENAME @"schema100_1Bonsai_2Lorem.touchdb"
#define TDDATABASEBLOBFILENAMESTESTS_NUMBER_OF_ATTACHMENTS 2
#define TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_01 @"3ff2989bccf52150bba806bae1db2e0b06ad6f88"
#define TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_02 @"d55f9ac778baf2256fa4de87aac61f590ebe66e0"

@interface TD_DatabaseBlobFilenamesTests : XCTestCase

@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) TD_Database *db;

@end

@implementation TD_DatabaseBlobFilenamesTests

- (void)setUp
{
    [super setUp];

    // Put setup code here. This method is called before the invocation of each test method in the
    // class.

    // Copy db with entries in attachment table
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *assetPath = [bundle
        pathForResource:[TDDATABASEBLOBFILENAMESTESTS_DBFILENAME stringByDeletingPathExtension]
                 ofType:[TDDATABASEBLOBFILENAMESTESTS_DBFILENAME pathExtension]];

    self.path = [NSTemporaryDirectory() stringByAppendingPathComponent:TDDATABASEBLOBFILENAMESTESTS_DBFILENAME];

    NSFileManager *defaultManager = [NSFileManager defaultManager];
    [defaultManager copyItemAtPath:assetPath toPath:self.path error:nil];

    // Open db
    self.db = [[TD_Database alloc] initWithPath:self.path];

    CDTEncryptionKeyNilProvider *provider = [CDTEncryptionKeyNilProvider provider];
    [self.db openWithEncryptionKeyProvider:provider];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the
    // class.

    // Remove copied db
    [self.db close];
    [TD_Database deleteClosedDatabaseAtPath:self.path error:nil];

    self.db = nil;
    self.path = nil;

    [super tearDown];
}

- (void)testAddTableToRelateKeysAndFilenamesToDatabaseSchema
{
    // Check db
    __block int count = 0;

    [self.db.fmdbQueue inDatabase:^(FMDatabase *db) {
      NSString *sql = [NSString
          stringWithFormat:
              @"SELECT COUNT(*) AS counts FROM sqlite_master WHERE type='table' AND name='%@'",
              TDDatabaseBlobFilenamesTableName];

      FMResultSet *result = [db executeQuery:sql];
      [result next];
      count = [result intForColumn:@"counts"];
      [result close];
    }];

    // Assert
    XCTAssertEqual(count, 1, @"Table %@ not found", TDDatabaseBlobFilenamesTableName);
}

- (void)testTableToRelateKeysAndFilenamesIsPreloaded
{
    // Query db
    __block int tableCount = 0;
    NSMutableSet *tableContent = [NSMutableSet set];

    [self.db.fmdbQueue inDatabase:^(FMDatabase *db) {
      NSString *sql = [NSString
          stringWithFormat:@"SELECT %@, %@ from %@", TDDatabaseBlobFilenamesColumnKey,
                           TDDatabaseBlobFilenamesColumnFilename, TDDatabaseBlobFilenamesTableName];

      FMResultSet *result = [db executeQuery:sql];
      while ([result next]) {
          tableCount++;

          NSString *hexKey = [result stringForColumn:TDDatabaseBlobFilenamesColumnKey];
          NSString *filename = [result stringForColumn:TDDatabaseBlobFilenamesColumnFilename];

          [tableContent addObject:@[ hexKey, filename ]];
      }
    }];

    // Expected result
    NSArray *oneBlob = @[
        TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_01,
        TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_01
    ];
    NSArray *otherBlob = @[
        TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_02,
        TDDATABASEBLOBFILENAMESTESTS_SHA1DIGEST_02
    ];
    NSSet *expectedContent = [NSSet setWithObjects:oneBlob, otherBlob, nil];

    // Assert
    XCTAssertEqual(tableCount, TDDATABASEBLOBFILENAMESTESTS_NUMBER_OF_ATTACHMENTS,
                   @"There are only %i blobs in this db",
                   TDDATABASEBLOBFILENAMESTESTS_NUMBER_OF_ATTACHMENTS);
    XCTAssertEqualObjects(tableContent, expectedContent,
                          @"After the first migration, filenames should be equal to the keys");
}

- (void)testDBVersionIsUpdatedAfterMigration
{
    __block int dbVersion = 0;

    [self.db.fmdbQueue inDatabase:^(FMDatabase *db) {
      dbVersion = [db intForQuery:@"PRAGMA user_version"];
    }];

    XCTAssertEqual(dbVersion, 101, @"Database version should be 101");
}

@end