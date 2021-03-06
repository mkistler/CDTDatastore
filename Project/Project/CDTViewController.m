//
//  CDTViewController.m
//  Project
//
//  Created by Michael Rhodes on 03/12/2013.
//  Copyright (c) 2013 Cloudant. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CDTViewController.h"

#import "CDTAppDelegate.h"
#import "CDTTodoReplicator.h"
#import "CDTTodo.h"

#import <CloudantSync.h>

@interface CDTViewController ()

@property (readonly) CDTDatastore *datastore;
@property (readonly) CDTTodoReplicator *todoReplicator;
@property (nonatomic, strong) NSArray *todoList;
@property (nonatomic,readonly) BOOL showOnlyCompleted;

@property (nonatomic,weak) UISegmentedControl *showCompletedSegmentedControl;

- (void)addTodoItem:(NSString*)item;
- (void)deleteTodoItem:(CDTDocumentRevision*)revision;
- (void)reloadTasks;

@end

@implementation CDTViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self reloadTasks];
    [self.tableView reloadData];
}

#pragma mark Data managment

/**
 Add a new todo for the item with the given `description`.
 */
- (void)addTodoItem:(NSString*)description {
    CDTTodo *todo = [[CDTTodo alloc] initWithDescription:description
                                               completed:NO];
    
    NSError *error;
    [self.datastore createDocumentFromRevision:todo.rev error:&error];

    if (error != nil) {
        NSLog(@"Error adding item: %@", error);
    }
}

/**
 Delete a todo item from the database.
 */
- (void)deleteTodoItem:(CDTTodo *)todo
{
    NSError *error;
    [self.datastore deleteDocumentFromRevision:todo.rev error:&error];

    if (error != nil) {
        NSLog(@"Error deleting item: %@", error);
    }
}

/**
 Toggle the completed state for a todo in the database.
 */
- (BOOL)toggleTodoCompletedForRevision:(CDTTodo *)todo
{
    NSLog(@"Toggling completed status for %@", todo.taskDescription);
    todo.completed = !todo.completed;

    NSError *error;
    [self.datastore updateDocumentFromRevision:todo.rev error:&error];

    if (error != nil) {
        NSLog(@"Error updating item: %@", error);
        return !todo.completed;  // we didn't manage to save the new revision
    }

    return todo.completed;
}


/**
 Load either active or completed todos based on the showOnlyCompleted property of
 the view controller.
 */
- (void)reloadTasks
{
    // Query for completed items based on whether we're showing only completed
    // items or active ones
    CDTQResultSet *result = [self.datastore find:@{@"completed": @(self.showOnlyCompleted)}];
    if (!result) {
        NSLog(@"Error querying for tasks.");
        exit(1);
    }

    NSMutableArray *tasks = [NSMutableArray array];
    [result enumerateObjectsUsingBlock:^(CDTDocumentRevision *rev, NSUInteger idx, BOOL *stop) {
        [tasks addObject:[[CDTTodo alloc] initWithDocumentRevision:rev]];
    }];

    self.todoList = [NSArray arrayWithArray:tasks];
}


#pragma mark Properties

/**
 The datastore is stored on the app delegate, this property is
 just shorthand for that.
 */
- (CDTDatastore *)datastore {
    CDTAppDelegate *delegate = (CDTAppDelegate *)[[UIApplication sharedApplication] delegate];
    return delegate.datastore;
}

-(CDTTodoReplicator *)todoReplicator {
    CDTAppDelegate *delegate = (CDTAppDelegate *)[[UIApplication sharedApplication] delegate];
    return delegate.todoReplicator;
}

-(BOOL)showOnlyCompleted {
    return self.showCompletedSegmentedControl.selectedSegmentIndex != 0;
}

#pragma mark Handlers

/**
 Adds a task using the text entered by the user.
 */
- (void)addTodoButtonTap:(NSObject *)sender {
    NSString *description = self.addTodoTextField.text;
    if (description.length == 0) { return; }  // don't create empty tasks
    NSLog(@"Adding task: %@", description);
    [self addTodoItem:description];
    [self reloadTasks];
    [self.tableView reloadData];
    self.addTodoTextField.text = @"";
}

/**
 Handler for clicking the sync button. Starts a sync using the
 CDTTodoReplicator class.
 */
-(IBAction)replicateTapped:(id)sender {
    NSLog(@"Replicate");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.todoReplicator sync];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadTasks];
            [self.tableView reloadData];
        });
    });
}

/**
 Handler for a change in the segmented view controller. Swaps between showing
 completed and active todos.
 */
-(void)toggleCompletedShown:(id)sender {
    [self refreshTodoList];
}

#pragma mark UITableView delegate methods

/**
 For todo items, selecting the cell toggles it's complete status.
 We also animate the transition between lists.
 */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"Selected row at [%li, %li]", (long)indexPath.section, (long)indexPath.row);
    if (indexPath.section == 1) {
        // Get the revision, toggle completed status on the body
        // and save a new revision, passing the current revision
        // ID and rev.
        CDTTodo *todo = [self.todoList objectAtIndex:indexPath.row];
        BOOL nowComplete = [self toggleTodoCompletedForRevision:todo];
        [self reloadTasks];

        // As we're using a segmented control, animate the change
        // so the item appears to be moving into the other list.
        UITableViewRowAnimation direction;
        if (nowComplete) {
            direction = UITableViewRowAnimationRight;
        } else {
            direction = UITableViewRowAnimationLeft;
        }
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:direction];
    }
}

/**
 Only todo items can be deleted, so only items from section 1.
 */
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1) {
        return YES;
    } else {
        return NO;
    }
}

/**
 Todo items can be deleted using the swipe-to-delete gesture.
 */
- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        CDTTodo *todo = [self.todoList objectAtIndex:indexPath.row];
        [self deleteTodoItem:todo];
        [self reloadTasks];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                              withRowAnimation:UITableViewRowAnimationLeft];
    }
}

#pragma mark UITableView data source methods

/**
 Section 0 contains the Add and Toggle View cells, so 2 cells there.
 Section 1 contains all the tasks visible in this view.
 */
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 2;
    } else {
        return self.todoList.count;
    }
}

/**
 First section for view controls, second section for todos.
 */
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}


/**
 Load appropriate cell prototype based on section and row.
 */
- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            // Add cell
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell"];
            self.addTodoTextField = (UITextField*)[cell viewWithTag:100];
            return cell;
        } else  {
            // Add cell
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompletedToggleCell"];

            self.showCompletedSegmentedControl = (UISegmentedControl*)[cell viewWithTag:101];
            [self.showCompletedSegmentedControl addTarget:self
                                                   action:@selector(toggleCompletedShown:)
                                         forControlEvents:UIControlEventValueChanged];
            
            return cell;
        }
    } else {
        // Item cell
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCell"];
        CDTTodo *todo = [self.todoList objectAtIndex:indexPath.row];
        cell.textLabel.text = todo.taskDescription;
        if (todo.completed) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }
}


#pragma mark UI animations

/**
 For fun, some simple animations between the two lists of todos.
 */
-(void)refreshTodoList
{
    [self.tableView beginUpdates];

    NSInteger oldCount = self.todoList.count;
    [self reloadTasks];
    NSInteger newCount = self.todoList.count;

    UITableViewRowAnimation directionIn, directionOut;
    if (self.showOnlyCompleted) {
        directionIn = UITableViewRowAnimationLeft;
        directionOut = UITableViewRowAnimationRight;
    } else {
        directionIn = UITableViewRowAnimationRight;
        directionOut = UITableViewRowAnimationLeft;
    }

    NSMutableArray *ips = [NSMutableArray array];

    if (oldCount > newCount) {
        for (int i = 0; i < newCount; i++) {
            [ips addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [self.tableView reloadRowsAtIndexPaths:ips withRowAnimation:directionIn];
        [ips removeAllObjects];

        for (NSInteger i = newCount; i < oldCount; i++) {
            [ips addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [self.tableView deleteRowsAtIndexPaths:ips withRowAnimation:directionIn];
    }

    if (newCount > oldCount) {
        for (int i = 0; i < oldCount; i++) {
            [ips addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [self.tableView reloadRowsAtIndexPaths:ips withRowAnimation:directionIn];
        [ips removeAllObjects];

        for (NSInteger i = oldCount; i < newCount; i++) {
            [ips addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [self.tableView insertRowsAtIndexPaths:ips withRowAnimation:directionOut];
    }

    if (newCount == oldCount) {
        for (int i = 0; i < oldCount; i++) {
            [ips addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [self.tableView reloadRowsAtIndexPaths:ips withRowAnimation:directionIn];
    }
    
    [self.tableView endUpdates];
}


@end
