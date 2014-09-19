//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Modifications for this distribution by Cloudant, Inc., Copyright (c) 2014 Cloudant, Inc.
//

#import "TDReplicator.h"
#import "TD_Revision.h"
@class TDChangeTracker, TDSequenceMap;


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
    BOOL _caughtUp;                     // Have I received all current _changes entries?
    TDSequenceMap* _pendingSequences;   // Received but not yet copied into local DB
    NSMutableArray* _revsToPull;        // Queue of TDPulledRevisions to download
    NSMutableArray* _deletedRevsToPull; // Separate lower-priority of deleted TDPulledRevisions
    NSMutableArray* _bulkRevsToPull;    // TDPulledRevisions that can be fetched in bulk
    NSUInteger _httpConnectionCount;    // Number of active NSURLConnections
    TDBatcher* _downloadsToInsert;      // Queue of TDPulledRevisions, with bodies, to insert in DB
    TDBatcher* _clientFilterNewDocsToInsert;  // Queue of missing revisions, specified by client Doc ID filter, but not in database yet

    NSArray* _clientFilterDocIds;
    
    // this is the set based on what we currently have
    NSMutableSet *_clientFilterCurrentSetDocIds;
    // this is any new ones
    NSMutableSet *_clientFilterNewDocIds;


}

// overrides
- (NSString*) remoteCheckpointDocID;
- (void) addToInbox: (TD_Revision*)rev;


- (void) setClientFilterDocIds:(NSArray *)clientFilterDocIds;

@end



/** A revision received from a remote server during a pull. Tracks the opaque remote sequence ID. */
@interface TDPulledRevision : TD_Revision
{
@private
    id _remoteSequenceID;
    bool _conflicted;
}

@property (copy) id remoteSequenceID;
@property bool conflicted;

@end
