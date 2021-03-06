//
//  ProfilesGeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "ProfilesGeneralPreferencesViewController.h"
#import "AdvancedWorkingDirectoryWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermLaunchServices.h"
#import "iTermProfilePreferences.h"
#import "iTermShortcutInputView.h"
#import "NSTextField+iTerm.h"
#import "ProfileListView.h"
#import "ProfileModel.h"
#import "PreferencePanel.h"

// Tags for _commandType matrix selectedCell.
static const NSInteger kCommandTypeCustomTag = 0;
static const NSInteger kCommandTypeLoginShellTag = 1;

// Tags for _initialDirectoryType
static const NSInteger kInitialDirectoryTypeCustomTag = 0;
static const NSInteger kInitialDirectoryTypeHomeTag = 1;
static const NSInteger kInitialDirectoryTypeRecycleTag = 2;
static const NSInteger kInitialDirectoryTypeAdvancedTag = 3;

static NSString *const iTermProfilePreferencesUpdateSessionName = @"iTermProfilePreferencesUpdateSessionName";

@interface ProfilesGeneralPreferencesViewController () <iTermShortcutInputViewDelegate, NSMenuDelegate, ProfileListViewDelegate>
@end

@implementation ProfilesGeneralPreferencesViewController {
    // Labels
    IBOutlet NSTextField *_basicsLabel;
    IBOutlet NSTextField *_shortcutLabel;
    IBOutlet NSTextField *_tagsLabel;
    IBOutlet NSTextField *_commandLabel;
    IBOutlet NSTextField *_sendTextAtStartLabel;
    IBOutlet NSTextField *_directoryLabel;
    IBOutlet NSTextField *_schemesHeaderLabel;
    IBOutlet NSTextField *_schemesLabel;

    // Controls
    IBOutlet NSTextField *_profileNameField;
    IBOutlet NSTextField *_profileNameFieldForEditCurrentSession;
    IBOutlet NSPopUpButton *_profileShortcut;
    IBOutlet NSTokenField *_tagsTokenField;
    IBOutlet NSMatrix *_commandType;  // Login shell vs custom command radio buttons
    IBOutlet NSTextField *_customCommand;  // Command to use instead of login shell
    IBOutlet NSTextField *_sendTextAtStart;
    IBOutlet NSMatrix *_initialDirectoryType;  // Home/Reuse/Custom/Advanced
    IBOutlet NSTextField *_customDirectory;  // Path to custom initial directory
    IBOutlet NSButton *_editAdvancedConfigButton;  // Advanced initial directory button
    IBOutlet AdvancedWorkingDirectoryWindowController *_advancedWorkingDirWindowController;
    IBOutlet NSPopUpButton *_urlSchemes;
    IBOutlet NSTextField *_badgeText;
    IBOutlet NSTextField *_badgeTextForEditCurrentSession;

    // Controls for Edit Info
    IBOutlet ProfileListView *_profiles;
    IBOutlet iTermShortcutInputView *_sessionHotkeyInputView;

    IBOutlet NSView *_editCurrentSessionView;
    IBOutlet NSButton *_copySettingsToProfile;
    IBOutlet NSButton *_copyProfleToSession;

    BOOL _profileNameChangePending;
    NSTimer *_timer;
}

- (void)dealloc {
    _profileNameFieldForEditCurrentSession.delegate = nil;
    [_timer invalidate];
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;

    info = [self defineControl:_profileNameField
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    __weak PreferenceInfo *weakInfo = info;
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
        assert(weakInfo);
        [strongSelf setString:strongSelf->_profileNameField.stringValue forKey:weakInfo.key];
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameDidChange];
    };
    info.willChange = ^() {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
    };

    info = [self defineControl:_profileNameFieldForEditCurrentSession
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    info.willChange = ^() {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
    };
    info.controlTextDidEndEditing = ^(NSNotification *notification) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameDidEndEditing];
    };

    [self defineControl:_profileShortcut
                    key:KEY_SHORTCUT
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self setShortcutValueToSelectedItem]; }
                 update:^BOOL { [self updateShortcutTitles]; return YES; }];

    [self defineControl:_tagsTokenField
                    key:KEY_TAGS
                   type:kPreferenceInfoTypeTokenField];

    [self defineControl:_commandType
                    key:KEY_CUSTOM_COMMAND
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self commandTypeDidChange]; }
                 update:^BOOL { [self updateCommandType]; return YES; }];

    info = [self defineControl:_customCommand
                           key:KEY_COMMAND_LINE
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return NO;
        }
        return [strongSelf->_commandType.selectedCell tag] == kCommandTypeCustomTag;
    };

    [self defineControl:_sendTextAtStart
                    key:KEY_INITIAL_TEXT
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_initialDirectoryType
                    key:KEY_CUSTOM_DIRECTORY
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self directoryTypeDidChange]; }
                 update:^BOOL { [self updateDirectoryType]; return YES; }];

    [self defineControl:_customDirectory
                    key:KEY_WORKING_DIRECTORY
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_badgeText
                    key:KEY_BADGE_FORMAT
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_badgeTextForEditCurrentSession
                    key:KEY_BADGE_FORMAT
                   type:kPreferenceInfoTypeStringTextField];

    [_profiles selectRowByGuid:[self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateProfileName)
                                                 name:iTermProfilePreferencesUpdateSessionName
                                               object:nil];
    [self updateEditAdvancedConfigButton];
}

- (void)windowWillClose {
    if (_profileNameChangePending) {
        [self updateProfileName];
    }
    [_timer invalidate];
    _timer = nil;
    if ([_tagsTokenField textFieldIsFirstResponder]) {
        // The token field's editor is the first responder. Force the token field to end editing
        // so the last token entered will be tokenized and prefs saved with it.
        [self.view.window makeFirstResponder:self.view];
    } else if ([_profileNameFieldForEditCurrentSession textFieldIsFirstResponder]) {
        [_profileDelegate profilesGeneralPreferencesNameDidEndEditing];
    }
}

- (NSArray *)keysForBulkCopy {
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:[_advancedWorkingDirWindowController allKeys]];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    self.view = _editCurrentSessionView;
}

- (void)reloadProfile {
    [super reloadProfile];
    [self populateBookmarkUrlSchemesFromProfile:[self.delegate profilePreferencesCurrentProfile]];
    [_profiles selectRowByGuid:[self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID]];
    _sessionHotkeyInputView.shortcut = [iTermShortcut shortcutWithDictionary:(NSDictionary *)[self objectForKey:KEY_SESSION_HOTKEY]];
}

- (NSString *)selectedGuid {
    return [_profiles selectedGuid];
}

#pragma mark - Copy current session to Profile

// Replace a Profile in the sessions profile with a new dictionary that preserves the original
// name and guid, takes all other fields from |bookmark|, and has KEY_ORIGINAL_GUID point at the
// guid of the profile from which all that data came.n
- (IBAction)changeProfile:(id)sender {
    NSString *guid = [_profiles selectedGuid];
    if (guid) {
        Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        Profile *origProfile = [self.delegate profilePreferencesCurrentProfile];
        NSString* origGuid = origProfile[KEY_GUID];
        [[ProfileModel sessionsInstance] setProfilePreservingGuidWithGuid:origGuid
                                                              fromProfile:bookmark];
        [self reloadProfile];
    }
}

#pragma mark - URL Schemes

- (BOOL)profileHandlesScheme:(NSString *)scheme {
    Profile *handler = [[iTermLaunchServices sharedInstance] profileForScheme:scheme];
    NSString *guid = [self stringForKey:KEY_GUID];
    return (handler &&
            [[handler objectForKey:KEY_GUID] isEqualToString:guid] &&
            [[iTermLaunchServices sharedInstance] iTermIsDefaultForScheme:scheme]);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.menu == _urlSchemes.menu) {
        menuItem.state = [self profileHandlesScheme:menuItem.title] ? NSOnState : NSOffState;
    }
    return YES;
}

- (IBAction)urlSchemeHandlerDidChange:(id)sender {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString *guid = profile[KEY_GUID];
    NSString *scheme = [[_urlSchemes selectedItem] title];
    iTermLaunchServices *schemeController = [iTermLaunchServices sharedInstance];
    NSString *boundGuid = [schemeController guidForScheme:scheme];
    if ([boundGuid isEqualToString:guid]) {
        [schemeController disconnectHandlerForScheme:scheme];
    } else {
        [schemeController connectBookmarkWithGuid:guid toScheme:scheme];
    }
    [self populateBookmarkUrlSchemesFromProfile:[[ProfileModel sharedInstance] bookmarkWithGuid:guid]];
}

- (void)populateBookmarkUrlSchemesFromProfile:(Profile*)profile {
    if ([[[_urlSchemes menu] itemArray] count] == 0) {
        NSArray* urlArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        [_urlSchemes addItemWithTitle:@"Select URL Schemes???"];
        for (NSDictionary *dict in urlArray) {
            NSString *scheme = dict[@"CFBundleURLSchemes"][0];
            [_urlSchemes addItemWithTitle:scheme];
        }
        [_urlSchemes setTitle:@"Select URL Schemes???"];
    }

    [[_urlSchemes menu] setAutoenablesItems:YES];
    [[_urlSchemes menu] setDelegate:self];
}

#pragma mark - Advanced initial directory settings

- (void)updateEditAdvancedConfigButton {
    NSString *directoryType = [self stringForKey:KEY_CUSTOM_DIRECTORY];
    BOOL isAdvanced = [directoryType isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue];
    [_editAdvancedConfigButton setEnabled:isAdvanced];
}

- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender {
    [_advancedWorkingDirWindowController window];  // force the window to load
    _advancedWorkingDirWindowController.profile = [self.delegate profilePreferencesCurrentProfile];
    __weak typeof(self) weakSelf = self;
    [self.view.window beginSheet:_advancedWorkingDirWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        for (NSString *key in [strongSelf->_advancedWorkingDirWindowController allKeys]) {
            [strongSelf setString:strongSelf->_advancedWorkingDirWindowController.profile[key] forKey:key];
        }
        [strongSelf->_advancedWorkingDirWindowController.window close];
    }];
}

#pragma mark - Directory type

- (void)directoryTypeDidChange {
    NSInteger tag = [[_initialDirectoryType selectedCell] tag];
    NSString *value;

    switch (tag) {
        case kInitialDirectoryTypeCustomTag:
            value = kProfilePreferenceInitialDirectoryCustomValue;
            break;

        case kInitialDirectoryTypeRecycleTag:
            value = kProfilePreferenceInitialDirectoryRecycleValue;
            break;

        case kInitialDirectoryTypeAdvancedTag:
            value = kProfilePreferenceInitialDirectoryAdvancedValue;
            break;

        case kInitialDirectoryTypeHomeTag:
        default:
            value = kProfilePreferenceInitialDirectoryHomeValue;
            break;
    }

    [self setString:value forKey:KEY_CUSTOM_DIRECTORY];
    [self updateEditAdvancedConfigButton];
}

- (void)updateDirectoryType {
    NSDictionary *map =
        @{ kProfilePreferenceInitialDirectoryCustomValue: @(kInitialDirectoryTypeCustomTag),
           kProfilePreferenceInitialDirectoryRecycleValue: @(kInitialDirectoryTypeRecycleTag),
           kProfilePreferenceInitialDirectoryAdvancedValue: @(kInitialDirectoryTypeAdvancedTag),
           kProfilePreferenceInitialDirectoryHomeValue: @(kInitialDirectoryTypeHomeTag) };
    NSString *value = [self stringForKey:KEY_CUSTOM_DIRECTORY];
    NSNumber *tagNumber = map[value];
    if (!tagNumber) {
        tagNumber = @(kInitialDirectoryTypeHomeTag);
    }
    [_initialDirectoryType selectCellWithTag:[tagNumber integerValue]];
    [self updateEditAdvancedConfigButton];
}

#pragma mark - Command Type

- (void)commandTypeDidChange {
    NSInteger tag = [[_commandType selectedCell] tag];
    NSString *value;
    if (tag == kCommandTypeCustomTag) {
        value = kProfilePreferenceCommandTypeCustomValue;
    } else {
        value = kProfilePreferenceCommandTypeLoginShellValue;
    }
    [self setString:value forKey:KEY_CUSTOM_COMMAND];
    [self updateEnabledState];
}

- (void)updateCommandType {
    NSString *value = [self stringForKey:KEY_CUSTOM_COMMAND];
    if ([value isEqualToString:kProfilePreferenceCommandTypeCustomValue]) {
        [_commandType selectCellWithTag:kCommandTypeCustomTag];
    } else {
        [_commandType selectCellWithTag:kCommandTypeLoginShellTag];
    }
    [self updateEnabledState];
}

#pragma mark - Shortcuts

- (void)setShortcutValueToSelectedItem {
    NSString* shortcut = [self shortcutKeyForTag:[[_profileShortcut selectedItem] tag]];
    if (shortcut) {
        Profile *currentProfile = [self.delegate profilePreferencesCurrentProfile];

        // If any profile has this shortcut, clear its shortcut.
        NSMutableArray *guidsOfProfilesToModify = [NSMutableArray array];
        for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
            NSString* existingShortcut = profile[KEY_SHORTCUT];
            if ([shortcut length] > 0 &&
                [existingShortcut isEqualToString:shortcut] &&
                profile != currentProfile) {
                [guidsOfProfilesToModify addObject:profile[KEY_GUID]];
            }
        }

        if (guidsOfProfilesToModify.count) {
            for (NSString *guid in guidsOfProfilesToModify) {
                Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
                [[ProfileModel sharedInstance] setObject:nil forKey:KEY_SHORTCUT inBookmark:profile];
            }
            [[ProfileModel sharedInstance] flush];
        }
    }
    [self setString:shortcut forKey:KEY_SHORTCUT];
    [self updateShortcutTitles];
    [[ProfileModel sharedInstance] flush];
}

- (NSString*)shortcutKeyForTag:(int)tag {
    if (tag == -1) {
        return @"";
    }
    if (tag >= 0 && tag <= 25) {
        return [NSString stringWithFormat:@"%c", 'A' + tag];
    }
    if (tag >= 100 && tag <= 109) {
        return [NSString stringWithFormat:@"%c", '0' + tag - 100];
    }
    return @"";
}

- (int)shortcutTagForKey:(NSString*)key {
    const char* chars = [key UTF8String];
    if (!chars || !*chars) {
        return -1;
    }
    char c = *chars;
    if (c >= 'A' && c <= 'Z') {
        return c - 'A';
    }
    if (c >= '0' && c <= '9') {
        return 100 + c - '0';
    }
    return -1;
}

- (void)updateShortcutTitles {
    // Reset titles of all shortcuts.
    for (NSMenuItem *item in _profileShortcut.menu.itemArray) {
        NSString *theKey = [self shortcutKeyForTag:[item tag]];
        if (theKey.length) {
            theKey = [@"??????" stringByAppendingString:theKey];
        }
        [item setTitle:theKey];
    }

    // Add bookmark names to shortcuts that are bound.
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    for (Profile *profile in [profileModel bookmarks]) {
        NSString* existingShortcut = profile[KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            const int theIndex = [_profileShortcut indexOfItemWithTag:tag];
            NSMenuItem *item = [_profileShortcut itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"??????%@ (%@)",
                                  existingShortcut, profile[KEY_NAME]];
            [item setTitle:newTitle];
        }
    }

    NSString *theString = [self stringForKey:KEY_SHORTCUT];
    [_profileShortcut selectItemWithTag:[self shortcutTagForKey:theString]];
    [_profileShortcut sizeToFit];
}

#pragma mark - NSTokenField delegate

- (NSArray *)tokenField:(NSTokenField *)tokenField
    completionsForSubstring:(NSString *)substring
               indexOfToken:(NSInteger)tokenIndex
        indexOfSelectedItem:(NSInteger *)selectedIndex {
    ProfileModel *model = [ProfileModel sharedInstance];
    NSArray *allTags = [[model allTags] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *aTag in allTags) {
        if ([aTag hasPrefix:substring]) {
            [result addObject:aTag];
        }
    }
    return result;
}

- (id)tokenField:(NSTokenField *)tokenField
    representedObjectForEditingString:(NSString *)editingString {
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - NSTokenFieldCell delegate

- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
    representedObjectForEditingString:(NSString *)editingString {
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - ProfileListViewDelegate

- (void)profileTableSelectionDidChange:(id)profileTable {
    [_copySettingsToProfile setEnabled:[_profiles hasSelection]];
    [_copyProfleToSession setEnabled:[_profiles hasSelection]];
}

- (void)profileTableRowSelected:(id)profileTable {
    [self changeProfile:self];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    [self setObject:view.shortcut.dictionaryValue forKey:KEY_SESSION_HOTKEY];
    [_profileDelegate profilesGeneralPreferencesSessionHotkeyDidChange];
}

#pragma mark - NSControlSubclassNotifications

- (void)controlTextDidChange:(NSNotification *)aNotification {
    id control = [aNotification object];
    if (control != _profileNameFieldForEditCurrentSession) {
        [super controlTextDidChange:aNotification];
    } else {
        _profileNameChangePending = YES;
        if (!_timer) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:0.75
                                                      target:self
                                                    selector:@selector(postUpdateSessionNameNotification:)
                                                    userInfo:nil
                                                     repeats:YES];
        }
    }
}

#pragma mark - Notifications

- (void)postUpdateSessionNameNotification:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermProfilePreferencesUpdateSessionName object:nil];
}

- (void)updateProfileName {
    if (_profileNameChangePending) {
        [self settingChanged:_profileNameFieldForEditCurrentSession];
        _profileNameChangePending = NO;
    }
}

@end
