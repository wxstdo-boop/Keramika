import 'package:flutter/widgets.dart';
import 'locale_provider.dart';
import '../models/alarm.dart';

class Translations {
  Translations._();

  /// Словари переводов в исходном виде — только для тестов.
  ///
  /// Отдаём наружу, чтобы тест паритета работал с настоящими данными
  /// приложения, а не с разбором исходника текстом: многострочные значения
  /// и значения в кавычках такой разбор ломает. Ключи приватные, поэтому
  /// наружу смотрит только сам тест.
  @visibleForTesting
  static Map<String, Map<String, String>> get rawData => _data;

  static const _data = <String, Map<String, String>>{
    'en': {
      'alarms': 'Alarms',
      'habits': 'Habits',
      'tasks': 'Tasks',
      'rc': 'RC',
      'realityChecks': 'Reality Checks',
      'settings': 'Settings',
      'statistics': 'Statistics',
      'nutrition': 'Nutrition',
      'calories': 'Calories',
      'meals': 'Meals',
      'timers': 'Timers',
      'categories': 'Categories',
      'category': 'Category',
      'all': 'All',
      'uncategorized': 'Uncategorized',
      'newCategory': 'New category',
      'categoryName': 'Category name',
      'manageCategories': 'Manage categories',
      'categoryExists': 'Category already exists',
      'createCategory': 'Create',
      'deleteCategory': 'Delete category',
      'deleteMealConfirmTitle': 'Delete meal?',
      'deleteMealConfirmBody':
          'This meal will be removed. This cannot be undone.',
      'deleteMealConfirm': 'Delete meal',
      'profile': 'Profile',
      'profileAnonymous': 'Anonymous',
      'profileName': 'Short name',
      'profileNameHint': 'What should we call you?',
      'profileNameSaved': 'Name saved',
      'profileOnlineTitle': 'Online status',
      'profileOnlineSwitch': 'Show the red dot',
      'profileOnlineSwitchDesc': 'Others will see you are around',
      'profileMusic': 'Your music',
      'profileMusicTrack': 'My track',
      'profileMusicEmpty': 'Add a track to play it in your profile',
      'profileMusicAdd': 'Pick a file',
      'profileMusicChange': 'Replace',
      'profileMusicSet': 'Music saved',
      'profileMusicFailed': 'Could not load the music',
      'profileMusicMissing': 'File not found',
      'profileMusicPlaying': 'Playing upbeat sound',
      'profileMusicPaused': 'Paused',
      'profileLeaderboard': 'Rating',
      'profileAddFriend': 'Add a friend',
      'profileNoFriends': 'Add friends to compare progress',
      'profileFriendsFull': 'The leaderboard already has 50 friends',
      'profileFriendName': 'Friend name',
      'profileFriendScore': 'Rating points',
      'profileFriendScoreRandom': 'Random points',
      'profileFriendScoreHint':
          'Points come from activity: habits, tasks, days in the log. '
              'More points — higher in the ranking.',
      'profileFriendSetScore': 'Points',
      'profilePickAvatar': 'Avatar',
      'profileAvatarFromGallery': 'Your own from the gallery',
      'profileAvatarSet': 'Avatar updated',
      'profileAvatarFailed': 'Could not load the avatar',
      'profileMe': 'Me',
      'profileEvents': 'Events',
      'eventNewYear': 'New Year event',
      'eventNewYearDesc': 'A new hat every day until January 1',
      'eventNewYearSoon': 'The event has not started yet',
      'eventCeramics': 'Ceramics fair',
      'eventCeramicsDesc': 'Workshops and firing for beginners',
      'eventCommunity': 'Community meetup',
      'eventCommunityDesc': 'Online gathering of keramika users, monthly',
      'about': 'About',
      'dataStorageError':
          'Local data could not be read or saved. Existing files were not changed.',
      'updateHashMissing':
          'The release has no valid SHA-256 digest. Installation was cancelled.',
      'updateInstalled': 'Updated to v{v}',
      'updateAvailable': 'Update available',
      'updateAvailableBody': 'Install v{v}?',
      'install': 'Install',
      'updateInstallBlocked':
          'The system blocked the update. Allow installs for this app and try again.',
      'updateInstallCancelled': 'Update cancelled',
      'open': 'Open',
      'patchNotes': 'Patch notes',
      'soon': 'Soon',
      'noAlarms': 'No alarms yet',
      'noHabits': 'No habits yet',
      'noTasks': 'No tasks yet',
      'noRealityChecks': 'No reality checks yet',
      'emptyAlarmHint': 'Set a gentle rhythm for your day in one minute.',
      'emptyAlarmAdvice':
          'Start with one reliable wake-up time. You can refine the sound and routine later.',
      'emptyHabitHint':
          'Give one small, repeatable action a place in your day.',
      'emptyHabitAdvice':
          'A habit becomes stronger when it is easy enough to repeat on an ordinary day.',
      'emptyTaskHint':
          'Keep the next important step visible and easy to finish.',
      'emptyTaskAdvice':
          'Write tasks as a single clear action. Small wins create momentum.',
      'emptyRealityHint': 'Turn an ordinary moment into a mindful pause.',
      'emptyRealityAdvice':
          'Choose one question you genuinely want to remember during the day.',
      'noTimers': 'No timers yet',
      'noMeals': 'No meals recorded yet',
      'theme': 'Theme',
      'language': 'Language',
      'light': 'Light',
      'dark': 'Dark',
      'system': 'System',
      'themeSystemLight': 'Sys. Light.',
      'peach': 'Peach',
      'grok': 'Grok',
      'rose': 'Rose', // Rose theme name
      'metel': 'Metel', // Gift theme name (transliterated, like Rose)
      'followSystem': 'Phone language',
      'english': 'English',
      'russian': 'Russian',
      'french': 'French',
      'data': 'Data',
      'export': 'Export',
      'import': 'Import',
      'exportDone': 'Settings exported',
      'importDone': 'Settings imported',
      'importError': 'Import failed',
      'importWrongFile': 'Please select a .json file',
      'license': 'License: MIT',
      'madeWithLove': 'Made with',
      'refresh': 'Refresh app',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'undo': 'Undo',
      'soundDeleted': 'Sound deleted',
      'ok': 'OK',
      'back': 'Back',
      'clear': 'Clear',
      'done': 'Done',
      'add': 'Add',
      'newAlarm': 'New alarm',
      'editAlarm': 'Edit alarm',
      'tapToChange': 'Tap to change',
      'repeat': 'Repeat',
      'wakeUpTask': 'Wake-up task',
      'taskNone': 'None',
      'taskMath': 'Solve math',
      'taskPattern': 'Tap pattern',
      'taskMemory': 'Memory game',
      'label': 'Label',
      'vibrate': 'Vibrate',
      'sound': 'Sound',
      'customSound': 'Custom',
      'pin': 'Pin alarm',
      'pinMeal': 'Pin',
      'unpinMeal': 'Unpin',
      'pinMsg': 'Pin',
      'unpinMsg': 'Unpin',
      'renameSound': 'Rename sound',
      'soundName': 'Sound name',
      'soundRenamed': 'Sound renamed',
      'soundRenameFailed': 'Could not rename sound',
      'labelOnce': 'Once',
      'labelEveryDay': 'Every day',
      'labelWeekdays': 'Weekdays',
      'labelWeekends': 'Weekends',
      'dayMon': 'Mon',
      'dayTue': 'Tue',
      'dayWed': 'Wed',
      'dayThu': 'Thu',
      'dayFri': 'Fri',
      'daySat': 'Sat',
      'daySun': 'Sun',
      'alarmNoExact':
          'Exact alarm permission not granted. Go to Settings → Apps → Agysha → Battery → No restrictions',
      'pinLock': 'PIN lock',
      'pinDescription': 'Set a PIN to lock the app',
      'setPin': 'Set PIN',
      'changePin': 'Change PIN',
      'removePin': 'Remove PIN',
      'enterPin': 'Enter PIN',
      'confirmPin': 'Confirm PIN',
      'wrongPin': 'Wrong PIN',
      'pinsDoNotMatch': 'PINs do not match',
      'exit': 'Exit',
      'exitConfirmTitle': 'Are you sure you want to take the green pill?',
      'exitConfirmBody': 'The “Exit” button closes the app.',
      'newHabit': 'New habit',
      'editHabit': 'Edit habit',
      'habitName': 'Habit name',
      'streak': 'streak',
      'habitType': 'Type',
      'habitTypeGood': 'Useful',
      'habitTypeBad': 'Harmful',
      'habitDays': 'Days of week',
      'remindAll': 'Remember it all',
      'remindAt': 'Remind at',
      'remindOffHint': 'Will remind about the habit at the chosen time',
      'remindOnHint': 'Every day or on selected days',
      'remindCustomText': 'Reminder text (max 60 chars)',
      'remindCustomHint': 'E.g.: Time to drink water',
      'habitDaysHint': 'Empty = every day',
      'everyDay': 'Every day',
      'habitNotesBtn': 'Status',
      'habitStatusTitle': 'Reminder',
      'habitStatusHint': 'Quick reminder',
      'habitNotesTitle': 'What you should remember',
      'habitNotesHint': 'Write what matters',
      'habitPinOnlyGood': 'Only useful habits can be pinned',
      'habitPinned': 'Habit pinned',
      'habitUnpinned': 'Habit unpinned',
      'habitsSectionGood': 'Useful',
      'habitsSectionBad': 'Harmful',
      'tasksSectionDone': 'Archived',
      'newTask': 'New task',
      'editTask': 'Edit task',
      'taskTitle': 'Task title',
      'completed': 'Completed',
      'description': 'Description',
      'notes': 'Notes',
      'priority': 'Priority',
      'priorityLow': 'Low',
      'priorityMedium': 'Medium',
      'priorityHigh': 'High',
      'dueDate': 'Due',
      'dueNone': 'No due date',
      'dueToday': 'Today',
      'dueTomorrow': 'Tomorrow',
      'dueIn3Days': 'In 3 days',
      'dueInWeek': 'In a week',
      'duePickDate': 'Pick a date',
      'estimate': 'Time limit',
      'estimateNone': 'No limit',
      'overdue': 'Overdue',
      'dragToReorder': 'Drag to reorder',
      'overallCompletion': 'Overall Completion',
      'doneToday': 'Done today',
      'refreshed': 'Refreshed',
      'newRc': 'New reality check',
      'editRc': 'Edit reality check',
      'rcQuestion': 'What to ask yourself?',
      'rcDone': 'Reality check done!',
      'rcToday': 'today',
      'rcChecks': 'checks total',
      'rcStat': 'Reality checks',
      'monthChartTitle': 'Last 30 days',
      'monthChartHabits': 'Habits',
      'monthChartTasks': 'Tasks',
      'monthChartBest': 'best day',
      'monthChartHint': 'Each bar is one day. Its height is how much got done — habits at the bottom, tasks on top. Today’s column is highlighted; the star marks the best day.',
      'monthChartDays': 'days done',
      'rcReset': 'Reset stats',
      'rcResetBody': 'Reset all check counts to zero?',
      'rcExit': 'Exit',
      'disableRcTitle': 'Disable reality checks?',
      'disableRcBody':
          'The section will fade out and the toggle will reappear. Reality-check stats will no longer be counted.',
      'disableRcLongHint': 'Long-press the title to turn off',
      'disable': 'Disable',
      // Settings card -- whole-section toggle for Reality Checks.
      'rcSettingsTitle': 'Reality Checks',
      'rcSettingsBody':
          'Adds or removes the section entirely: the “RC” tab in Home, schedule and notifications.',
      'rcSettingsOn': 'Reality Checks section enabled',
      'rcSettingsOff': 'Reality Checks section hidden',
      'rcChecksPerDay': 'Checks per day',
      'rcTimeRange': 'Time range',
      'rcFrom': 'From',
      'rcTo': 'To',
      'rcScheduled': 'scheduled',
      'rcText1': 'Is this a dream?',
      'rcText2': 'Look at your hands. Can you count the fingers?',
      'rcText3': 'Try to push your finger through your palm.',
      'rcText4': 'Read this sentence twice. Does the text change?',
      'rcText5': 'Look around — do you really know this place?',
      'rcText6': 'What did you do ten minutes ago? Was it real?',
      'rcText7': 'Touch the nearest wall. Does the texture feel right?',
      'rcText8': 'Say your name out loud. Did it sound like you?',
      'perfectionism': 'Fight Perfectionism',
      'perfectionismHint': 'Daily anti-perfectionism scroll',
      'perfTitle1': 'OCD',
      'perfTitle2': 'Imperfection',
      'perfTitle3': 'Stupor',
      'perfTitle4': 'All-or-Nothing',
      'perfTitle5': 'Procrastination',
      'perfTitle6': 'Self-Criticism',
      'perfTitle7': 'Mental Rituals',
      'perfTitle8': 'Intolerance',
      'perfTitle9': 'Overcontrol',
      'perfTitle10': 'Stillness is not laziness',
      'perfTitle11': 'Shame loop',
      'perfTitle12': 'Scanning',
      'perfTitle13': 'Grounding',
      'perfTitle14': 'Body signal',
      'perfTitle15': 'Idea trap',
      'perfTitle16': 'Self-improvement as ritual',
      'perfTitle17': 'Balance',
      'perfTitle18': 'Exploration',
      'perfTitle19': 'Growth through mess',
      'perfTitle20': 'Objects tell stories',
      'perf1Short': 'Allow messiness.',
      'perf2Short': 'Micro step beats freeze.',
      'perf3Short': 'Small today > big plan.',
      'perf4Short': 'Done is enough. Perfect is enemy.',
      'perf5Short': 'Procrastination = fear, not laziness.',
      'perf6Short': 'Words are not a sentence.',
      'perf7Short': 'Name the loop and break it.',
      'perf8Short': 'Uncertainty is not danger.',
      'perf9Short': 'Let go to gain control.',
      'perf10Short': 'Pause ≠ flaw.',
      'perf11Short': 'Shame does not build you.',
      'perf12Short': 'Don’t look for problems — live.',
      'perf13Short': 'Feel your feet, you are here.',
      'perf14Short': 'Your body signals truth.',
      'perf15Short': 'Thinking is not doing.',
      'perf16Short': 'Not every improvement is progress.',
      'perf17Short': 'Stability before intensity.',
      'perf18Short': 'Curiosity is a way out.',
      'perf19Short': 'Dirt is part of the art.',
      'perf20Short': 'Everything around you has been chosen.',
      'perf1Full':
          'Mess is not the enemy.\nA slightly crooked shelf is still a shelf.\nDone beats clean.\nProgress > perfection.',
      'perf2Full':
          'Imperfection is also fine.\nNegative feedback is part of the work, not a verdict.\nClose your eyes, take one tiny step and continue.\nYou don’t need to be perfect to move forward.',
      'perf3Full':
          'Stupor is a signal, not a wall.\nTake a micro step: one line, one click.\nMovement kills fear.\nNow is the time to do something small.',
      'perf4Full':
          'Done is enough.\nPerfect is the enemy of good.\nStart ugly. You can refine later.\nMotion beats perfection.',
      'perf5Full':
          'Procrastination = fear of the result, not laziness.\nStart for 2 minutes — the body will want more.\nAction burns anxiety.\nAny beginning beats fear.',
      'perf6Full':
          'You are already doing. Self-destruction won’t speed up growth.\nBe to yourself what you would be to a friend.\nTurn down the volume of the inner critic.\nSoftness gives more than yelling.',
      'perf7Full':
          'The mind loops the same thought.\nName it: “this is OCD” and look away.\nDo not solve — observe.\nEach return weaker than the last.',
      'perf8Full':
          'The need to know everything is a trap.\nLive the question.\nTolerate not-knowing.\nCertainty is a fantasy; courage is real.',
      'perf9Full':
          'Tightening every screw exhausts you.\nLoosen the grip.\nDo less, but mean it.\nFreedom lives in the gap between stimulus and response.',
      'perf10Full':
          'Resting is not quitting.\nThe pause can be the most productive thing.\nSit with it. Breathe. Return when ready.',
      'perf11Full':
          'Shame loops trap you into inaction.\nName it. It softens.\nYou are still on the way.',
      'perf12Full':
          'Stop examining the world under a magnifying glass.\nThe flaws you hunt for are invisible to anyone else.\nThere is no danger — only a tense focus.\nWiden the window, calm inside.',
      'perf13Full':
          'When thoughts run wild, press your feet into the floor.\nCold air. Light sound.\nFive things you see right now.\nThis moment is enough.',
      'perf14Full':
          'The body speaks more honestly than the mind.\nAnxiety tightens the shoulders; fear grips the gut.\nBefore thinking, listen.\nIt knows first and doesn’t lie.',
      'perf15Full':
          'A perfect plan in your head counts for nothing.\nWrite one bad sentence. Make one ugly move.\nDoing beats planning every time.',
      'perf16Full':
          'Collecting tips, reading advice, tweaking routines — these can be a ritual too.\nAsk: did I actually do something today?',
      'perf17Full':
          'Small daily actions beat heroic bursts.\nOne minute of breathing > one hour of overthinking.\nChoose the path that lasts.',
      'perf18Full':
          'Curiosity is the antidote to perfectionism.\nAsk: what happens if I try it differently?\nA mistake is reconnaissance, not failure.\nThe way is more interesting than the result.',
      'perf19Full':
          'Imperfection leaves marks that prove you were there.\nClean surfaces hide the hand.\nYour mess has value.',
      'perf20Full':
          'Look at five objects in the room.\nEach was made by someone who struggled, adapted, and tried again.\nYou are part of that chain.',
      'wtTest': 'Test task',
      'wtSolved': 'Great job! You are awake!',
      'wtDismiss': 'Dismiss alarm',
      'wtWrong': 'Wrong! Try again.',
      'wtMathTitle': 'Solve this to dismiss the alarm',
      'wtAnswerHint': 'Enter the answer',
      'wtCheck': 'Check',
      'wtPatternTitle': 'Memorize the sequence, then tap it',
      'wtPatternWatch': 'Watch carefully',
      'wtMemoryTitle': 'Remember the numbers, then type them',
      'overthinking': 'Overthinking',
      'procrastination': 'Procrastination',
      'selfCriticism': 'Self-criticism',
      'notifications': 'Notifications',
      'notificationsDesc': 'Enable or disable all notifications',
      'batteryOptimization': 'Battery optimization',
      'batteryOptDesc': 'Disable for reliable alarms',
      'batteryOpened': 'Battery settings opened',
      'batterySettings': 'Battery settings',
      'batterySettingsDesc': 'Disable optimization for reliable alarms',
      'fullscreenNotif': 'Full-screen notifications',
      'fullscreenNotifDesc': 'Show alarm over lock screen',
      'fullScreenNotifTitle': 'Full-screen notifications',
      'fullScreenNotifBody': 'Required for alarm to show over lock screen',
      'fullScreenGrantMissing':
          'The system turned off full-screen display. The alarm will still open its screen, but it is safer to allow it.',
      'autostart': 'Autostart',
      'autostartDesc': 'Allow alarm to fire when app is closed',
      'popupWarningTitle': 'Important!',
      'popupWarningBody':
          'For alarms to fire reliably, please allow notifications and full-screen intent.',
      'popupWarningOpen': 'Open settings',
      'popupWarningDismiss': 'Later',
      'dontShowAgain': 'Don’t show again',
      'settingsCantOpen':
          'Cannot open settings. Open the app settings → Notifications / Battery manually.',
      'welcomeTitle': 'Welcome to Agysha!',
      'welcomeBody':
          'Important: allow notifications and unrestricted background activity so alarms can ring on time. You can adjust these permissions now or later in Settings.',
      'welcomeGo': 'Go to settings',
      'welcomeSkip': 'Skip',
      'maxAlarms': 'Max 10 alarms',
      'maxHabits': 'Max 100 habits',
      'maxTasks': 'Max 150 tasks',
      'maxRc': 'Max 1 reality check',
      'maxTimers': 'Max 5 timers',
      'maxCat': 'Max {n} categories',
      'maxCal': 'Max 10000 kcal',
      'maxCalPerMeal': 'Max 10000 kcal per meal',
      'fillAllFields': 'Please fill all fields',
      'mealAdded': 'Meal added successfully',
      'kcalShort': 'kcal',
      'mlShort': 'ml',
      'water': 'Water',
      'waterField': 'Water, ml',
      'calorieNorm': 'Daily limit',
      'ofPrefix': 'of',
      'normSaved': 'Norm saved',
      'mealsToday': 'Meals today',
      'macroP': 'Protein',
      'macroF': 'Fat',
      'macroC': 'Carbs',
      'macroPSingle': 'P',
      'macroFSingle': 'F',
      'macroCSingle': 'C',
      'trends': 'Trends',
      'trendsWindow': 'Last {n} days',
      'avgPerDay': 'Avg per day',
      'daysOnTarget': 'days on target',
      'bestDay': 'best day',
      'maxWaterPerMeal': 'Max 3000 ml per meal',
      'needNameOrWater': 'Enter a dish or water',
      'maxDigitsHit': 'No more digits',
      'clearAll': 'Clear',
      'backspace': 'Backspace',
      'diagnostics': 'Diagnostics',
      'diagAlarmTest': 'Test alarm notification',
      'testAlarm': 'Test alarm',
      'diagRcTest': 'Test RC notification',
      'diagSoundTest': 'Test default sound',
      'diagSent': 'Notification sent!',
      'diagSoundPlayed': 'Sound played!',
      'diagNotEnabled': 'Notifications are disabled',
      'diagEnableNotif':
          'Notifications are off — open settings to enable them.',
      'diagError': 'Error',
      'resetWarnings': 'Reset warnings',
      'warningsResetDone': 'Warnings reset — they will appear again',
      'mildImprovements': 'Mild improvements',
      'experimentalSettings': 'Experimental',
      'experimentalDesc': 'Show/hide the timers section (timers are kept)',
      'aiGuide': 'AI guide',
      'aiGuideSub': 'Habit coach',
      'adaName': 'Ada',
      'adaTagline': 'nothing needed',
      'aiClear': 'Clear chat',
      'aiUndo': 'Undo',
      'aiWindow': 'Collapse to window',
      'aiWindowOff': 'Turn off window',
      'aiWindowHint': 'Collapsed to a mini window — drag it, tap it to return',
      'aiSystemWindowHint':
          'Ada is now a mini window above other apps — close it there',
      'aiOverlayPermissionHint':
          'Allow Agysha to draw over other apps to enable the mini window',
      'aiOverlayEmpty': 'Chat with Ada',
      'aiInputHint': 'Message…',
      'pinLimit': 'You can pin up to 10 messages',
      'adaTracking': 'Ada tracking',
      'adaTrackingDesc':
          'Ada writes the morning report at 08:00 and the evening review at 21:00 right into the chat — no notifications needed.',
      'adaTrackingOn':
          'Ada now writes to the chat every day at 08:00 and 21:00',
      'adaQuota': 'Ada: N free left today',
      'aiChipHabit': 'Habit',
      'aiChipTask': 'Task',
      'aiChipAlarm': 'Alarm',
      'aiChipRC': 'Reality check',
      'aiChipMeal': 'Meal',
      'aiWebSearch': 'Web search',
      'aiWebSearchOn': 'Web search ON',
      'adaEmptyChat': 'Ada will pave the way ―\neither there, or there',
      'readReceipt': 'Read',
      'readReceiptAt': 'Read at',
      'aiGuideHint': 'Ask me',
      'aiComposing': 'Composing',
      'aiEmptyAnswer': 'Hmm, I could not craft an answer. Try again!',
      'share': 'Share',
      'aiGuideToggle': 'Enable AI guide',
      'aiGuideDesc':
          'A small circle appears next to the “+” button and opens a mini chat.',
      'aiGuideKey': 'Poolside key (optional)',
      'aiGuideKeyHint': 'Paste your Laguna API key',
      'aiGuideKeyNote':
          'Free providers: Kilo, OVHcloud, Murakumo and AI Horde. Poolside key is optional.',
      'aiGuideKeyNoteProviders': 'Kilo, OVHcloud, Murakumo and AI Horde',
      'aiGuideKeyNoteTail': '',
      'geminiKey': 'Gemini key (optional — the best, hottest Ada)',
      'geminiKeyHint': 'Paste your Google AI Studio key',
      'freeFallbacks': 'Free fallbacks:',
      'aiResort': 'AI is on vacation, wait a bit',
      'retry': 'Retry',
      'changeIcon': 'Change icon',
      'chooseIcon': 'Choose icon',
      'timeMode': 'Time mode',
      'addTime': 'Add time',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'todayErased': 'Today cleared',
      'changelogTitle': 'What’s new',
      'dailyMotivation': 'Daily Motivation',
      'addMeal': 'Add meal',
      'tipSugarTitle': 'Sugar shield',
      'tipSugarBody':
          'If the sweet is in packaging, it wants to stay at the store. Pick fruit, dark chocolate or water.',
      'tipSugarBody2':
          'Protein keeps you full longer. Add an egg, yogurt, or nuts to every meal and snacks will stop haunting you.',
      'tipWaterTitle': 'Water first',
      'tipWaterBody':
          'Often thirst wears a hunger mask. Drink a glass of water and wait 10 minutes before refilling your plate.',
      'tipProteinTitle': 'Protein anchor',
      'tipProteinBody':
          'Protein keeps you full longer. Add an egg, yogurt, or nuts to every meal and snacks will stop haunting you.',
      'tipWalkTitle': 'Take a walk',
      'tipWalkBody': 'A 10-minute walk kills a craving faster than willpower.',
      'tipCoffeeTitle': 'Black coffee',
      'tipCoffeeBody':
          'One black coffee can kill sugar craving for 30-40 minutes.',
      'tipColdWaterTitle': 'Ice-cold water',
      'tipColdWaterBody':
          'A glass of ice water instantly resets mind and body — the cold shock breaks the craving loop.',
      'tipMindfulTitle': 'Eat with awareness',
      'tipMindfulBody':
          'Put the phone down and chew slowly. In 20 minutes your brain finally catches up with your stomach.',
      'tipSleepTitle': 'Sleep controls appetite',
      'tipSleepBody':
          'Less than 7 hours spikes hunger hormones. Protect your sleep schedule and late-night cravings weaken.',
      'tipVeggiesTitle': 'Veggies first',
      'tipVeggiesBody':
          'Start every meal with vegetables or salad. Fiber fills you up before the heavier food even reaches the table.',
      'tipChewTitle': 'Chew count',
      'tipChewBody':
          'Try 20 chews per bite. It slows you down, improves digestion and naturally cuts portion size without suffering.',
      'tipFiberTitle': 'Fiber beats hunger',
      'tipFiberBody':
          'Whole grains and vegetables keep you satisfied longer than refined carbs.',
      'tipNoSnackTitle': 'Skip the snack aisle',
      'tipNoSnackBody':
          'If you’re not hungry enough to eat an apple, you’re probably bored or thirsty.',
      'tipSpicesTitle': 'Spice it up',
      'tipSpicesBody':
          'Strong flavors signal satisfaction faster. Add herbs, chili, or citrus to slow down eating.',
      'tipBreakfastTitle': 'Breakfast anchor',
      'tipBreakfastBody':
          'A protein-rich start prevents mid-morning crashes and random snacking.',
      'tipPortionTitle': 'Smaller plate, same meal',
      'tipPortionBody':
          'Visual cues fool the brain. A smaller plate fills you up with less food.',
      'tipAlcoholTitle': 'Alcohol lowers brakes',
      'tipAlcoholBody':
          'Even one drink reduces self-control and increases late-night food cravings.',
      'tipMindfulHungerTitle': 'Name your hunger',
      'tipMindfulHungerBody':
          'Ask: is this real hunger, a craving, or emotional eating? Labeling it reduces the impulse.',
      'tipConsistencyTitle': 'Same rhythm',
      'tipConsistencyBody':
          'Eating at regular times stabilizes blood sugar. Random meals confuse your metabolism.',
      'tipFruitCravingTitle': 'Fruit > Sugar',
      'tipFruitCravingBody':
          'An apple or berries satisfy the sweet tooth without the sugar spike.',
      'tipDarkChocolateTitle': 'Dark chocolate',
      'tipDarkChocolateBody':
          'Two squares of 85% dark chocolate satisfy the temptation without the guilt.',
      'tipYogurtTitle': 'Yogurt with berries',
      'tipYogurtBody':
          'Plain yogurt with berries is a dessert without false shame that feels indulgent.',
      'tipWarmDrinkTitle': 'Hot drink',
      'tipWarmDrinkBody': 'A warm sugar-free drink calms sweet cravings.',
      'tipReplaceTitle': 'Replace, don’t ban',
      'tipReplaceBody':
          'The brain resists bans; it reacts better to replacement.',
      'tipStressSugarTitle': 'Stress ≠ Sugar',
      'tipStressSugarBody':
          'Stress spikes sugar cravings. Walk it off instead.',
      'tipWaitTitle': '10-minute rule',
      'tipWaitBody':
          'Wait 10 minutes before giving in to a craving — most of them fade on their own.',
      'tipOvereatTitle': 'Don’t eat to bursting',
      'tipOvereatBody':
          'Stop when comfortable, not stuffed. It takes 20 minutes for the brain to register fullness.',
      'tipSugarSwapTitle': 'Swap the sugar',
      'tipSugarSwapBody':
          'Craving sweets? Reach for fruit, a square of dark chocolate or cinnamon tea — the taste is there, the spike is not.',
      'tipSaltBloatTitle': 'Less salt, less bloat',
      'tipSaltBloatBody':
          'Salty snacks and sauces hold water in. Season with herbs, lemon and spices instead — the puffiness drops in a couple of days.',
      'tipPotassiumTitle': 'Potassium against puffiness',
      'tipPotassiumBody':
          'Bananas, greens, avocado and beans help push excess water out. Add one to every meal.',
      'tipWaterBloatTitle': 'Water flushes water',
      'tipWaterBloatBody':
          'When you drink too little, the body stores fluid. 6–8 glasses a day is the simplest anti-bloat habit.',
      'tipLateSaltTitle': 'No salt at night',
      'tipLateSaltBody':
          'A salty dinner shows up on the face by morning. Keep the evening meal light and low-salt.',
      'tipMoveBloatTitle': 'Move to drain',
      'tipMoveBloatBody':
          'A 20-minute walk or a light workout gets the lymph moving and the puffiness visibly down.',
      'tipProcessedTitle': 'Skip processed food',
      'tipProcessedBody':
          'Sausages, chips and ready meals are salt bombs. Cook from whole foods and the swelling eases.',
      'tipHerbalTitle': 'Herbal teas',
      'tipHerbalBody':
          'Dandelion, nettle and green tea gently support the kidneys and help shed excess water.',
      'tipSwellingCheckTitle': 'When to see a doctor',
      'tipSwellingCheckBody':
          'If puffiness stays for weeks, is one-sided or comes with pain — see a doctor rather than dieting it away.',
      'newTimer': 'New timer',
      'editTimer': 'Edit timer',
      'timerDuration': 'Duration',
      'timerLabel': 'Label',
      'timerDone': 'Timer done!',
      'timerRunning': 'Running',
      'timerPaused': 'Paused',
      'timerFinished': 'Finished',
      'autoSave': 'Auto-save',
      'autoSaveDesc': 'Save data every second',
      'autoExport': 'Auto-export',
      'autoExportHourly': 'Save backup to Download/Agysha every hour',
      'autoExportDone': 'Backup saved to Download/Agysha',
      'autoExportFailed': 'Could not save the backup',
      'clearCache': 'Clear cache',
      'clearCacheDesc': 'Free up storage used by temporary files',
      'clearCacheDone': 'Cache cleared!',
      'haptics': 'Vibration',
      'hapticsDesc': 'Short vibration on taps and switches',
      'sounds': 'Sounds',
      'soundsDesc': 'Soft system click on confirmations',
      'reduceMotion': 'Reduce motion',
      'reduceMotionDesc': 'Turn off decorative animations and effects',
      'devMode': 'Developer mode',
      'devModePrompt': 'Enter the access code to continue',
      'devModeInvalidCode': 'That code did not match. Try again.',
      'devModeUnlock': 'Unlock',
      'devToolsTitle': 'Developer tools',
      'devToolsSubtitle': 'Hidden settings for fine-polishing the app.',
      'devModeDisable': 'Turn off developer mode',
      'devPromptTitle': 'What should change in the app?',
      'devPromptDescription':
          'Write down the improvements you want to make. This note is saved automatically and included in your backup.',
      'devPromptHint':
          'Describe the changes, behavior, or design you would like...',
      'devPromptSaving': 'Saving…',
      'devPromptSaved': 'Saved on this device',
      'devPromptUnsaved': 'Changes not saved yet',
      'devPromptSaveError': 'Could not save. Tap Save to try again.',
      'devPromptSave': 'Save',
      'forgeTitle': 'Forge',
      'forgeSubtitle': 'Chat with the agent: ask about the code or ask it to change it.',
      'forgeTokenSection': 'GITHUB ACCESS',
      'forgeTokenHint': 'Fine-grained: Contents, Pull requests — read and write.',
      'startupDiagTitle': 'Agysha stopped safely',
      'startupDiagBody':
          'Agysha could not finish starting and stopped before it drew the '
          'first screen. Nothing was changed on disk. You can retry, or '
          'copy/save the details below to report the problem.',
      'startupDiagDetailsTitle': 'Technical details',
      'startupDiagCopy': 'Copy',
      'startupDiagSave': 'Save log',
      'startupDiagSaved': 'Log saved:',
      'startupDiagSaveFailed': 'Could not save the log to a file.',
      'startupDiagCopied': 'Copied to clipboard.',
      'startupDiagRetry': 'Try again',
      'startupDiagRetrying': 'Retrying…',
      'startupDiagRetryFailed':
          'Restart did not succeed. The error below is unchanged.',
      'forgeTokenCheck': 'Save',
      'forgeTokenForget': 'Forget token',
      'forgeTokenOk': 'Token works',
      'forgeTokenInvalid': 'GitHub rejected the token',
      'forgeTokenReadOnly': 'No write access — the agent cannot commit',
      'forgeTokenEmpty': 'Token needed',
      'forgeTokenSaveFailed': 'Could not save the token — storage unavailable',
      'forgeTokenForgotten': 'Token removed',
      'forgeChatSection': 'CHAT',
      'forgeTaskHint': 'Ask about the code or describe a change…',
      'forgeRun': 'Send',
      'forgeWorking': 'Working…',
      'forgeTaskEmpty': 'Task needed',
      'forgeProvider': 'free provider',
      'forgeLogSection': 'LOG',
      'forgeDone': 'Pull request ready',
      'forgeBranch': 'Branch',
      'forgeFiles': 'files changed',
      'forgeSafetyNote':
          'Questions are answered right away. Edits go to a branch and a pull request — main is untouched. AI: built-in free providers.',
      'forgeThinking': 'Agent is thinking…',
      'forgeChatEmpty':
          'Ask a question about the project or describe what to change.',
      'forgeClearChat': 'Clear chat',
      'forgeChatCleared': 'Chat cleared',
      'forgeChanges': 'Changes',
      'forgeNoChanges': 'No edits this turn',
      'showPassword': 'Show code',
      'hidePassword': 'Hide code',
      'patchDeveloping': 'How the app is developing',
      'patchRoadmap': 'Minor tweaks, PR in 2027',
      'changeSwipeUp': 'Swipe up on the home screen to refresh',
      'changeAdaGuide':
          'AI guide Ada — a mini chat that creates habits, tasks, alarms, reality checks and meals by itself',
      'changeSmoothAnim':
          'Smooth animations everywhere: section transitions, settings, cards, toggles',
      'changeStreakFix': 'Fixed streaks and habit check-offs',
      'changePinBlur': 'PIN lock now blurs the app in recent apps',
      'changeNotifIcon': 'Notification icon — signature K badge',
      'changeAlarmFix': 'Alarms: sounds restored, time picker works with drag',
      'changeTaskShelvesContrast':
          'Task shelves: headings are now readable in both light and dark themes',
      'changeLintCleanup':
          'Tidied up the internals — the app is a little more dependable now',
      'changeTaskShelves': 'Tasks are split into "Active" and "Completed" shelves',
      'changeTaskMarkFinal':
          'Completing a task is final — it moves to the completed shelf',
      'changeCIUpdate':
          'Releases go out more smoothly — we reworked the build pipeline',
      'changeCategoryDrag':
          'Categories can be dragged to reorder them in the task editor',
      'changeCategoryReorder':
          'Category order changes smoothly and is remembered',
      'changeRemindAllCircle':
          '"Remind all" now matches the tone of the buttons next to it',
      'changePinSmooth':
          'The lock screen and habit ring animate smoothly',
      'changeFlockEdges':
          'The flock of birds fades in and out instead of being cut off',
      'changeForgeTokenSave':
          'Forge: saving a GitHub token now works — the button comes back to life',
      'changeForgeAgent':
          'Forge is a real chat agent: it answers questions and edits the code',
      'changeForgePr':
          'Agent changes go to a branch and open a pull request for review',
      'changeForgeFree':
          'Forge works out of the box on built-in free providers — no API key needed',
      'changeForgeSection':
          'Developer Corner gained the Forge section for repository edits',
      'changeForgeEntry': 'Forge is reachable from Settings, in three languages',
      'changeCIMemory':
          'Release builds no longer fail on the runner for lack of Gradle memory',
      'changeCISigning':
          'Signing secrets are checked upfront, with a clear error instead of a crash',
      'changeAutoUpdateName':
          'Auto-update compares versions by name, so it works with split APKs',
      'changeHamster':
          'Hamster: statistics, search and a faster PIN screen',
      'changeMutilatedTheme':
          'New theme MUTILATED — light bloody red with faint splatter overlay',
      'changeElegantEgg':
          "Hold the MUTILATED chip for 10 seconds to reveal 'Are you elegant?' easter egg",
      'changeMealConfirm': 'Confirmation dialog before deleting a meal entry',
      'changeChatScroll':
          'AI chat now sticks to the last message while streaming and on open',
      'changeLangSmooth': 'Smoother language switching transition',
      'changeEmDash':
          'All visible dashes are now long em-dashes across the app',
      'changeSplashFix': 'Splash avatar no longer flickers on cold start',
      'aboutAuthorTitle': 'About the author',
      'visitellaName': 'Visitella',
      'visitellaDesc': 'Projects, games, news',
      'aboutAuthorBody': 'Other apps by the same developer:',
      'supportAuthorTitle': 'Support the author',
      'supportAuthorBody':
          'Agysha is a solo project — no ads, no subscriptions. If it makes your days easier, treat the author to a coffee: the best thank-you there is.',
      'supportAuthorHint': 'Opens the thank-you page in your browser',
      'supportSoonToast': 'Ozon support is on its way — coming very soon!',
      'supportOzonSubtitle': 'Soon — support with a purchase',
      'supportBoostySubtitle': 'One-time donation or subscription',
      'support': 'Buy me a coffee',
      'rcNotificationTitle': 'Reality Check',
      'appMisasoc': 'Misasoc',
      'appAtaraxy': 'Ataraxy',
      'changeHabitLayout':
          'Habit cards redesigned: completion checkbox on top, habit type icon below',
      'changeHabitFit':
          'Habit rows now fit long titles, notes and day labels nicely',
      'changePerfectionismTitle':
          'Perfectionism plaques now use proper title case',
      'changeHabitStreak':
          'Brought back the 7-day streak dots on each habit card',
      'changeHabitSections':
          'Habits now split into Useful / Harmful sections when you have both types',
      'changeAlarmSounds':
          'Removed alarm sounds stay removed across new alarms',
      'changeTimerSounds':
          'Removed timer sounds stay removed across new timers',
      'changeRcRandom':
          'Reality check notifications now fire at random times with random built-in question texts',
      'changeGrokTheme': 'Grok theme switched to monochrome light/dark',
      'changeMealCards':
          'Nutrition cards now use a daily randomized set of colors and icons',
      'changeDropdowns': 'Dropdowns are now rounded in settings and tasks',
      'changeSnackbar': 'Snackbar animation polished',
      'changeSwipeSnap':
          'Swipe between sections now snaps smoothly instead of free-floating',
      'changeCornerSwipe':
          'Top corners are rounded during the swipe transition',
      'changeRoundedTiles': 'Settings tiles are now rounded',
      'changeCategoryLimit': 'Category name limit reduced to 15 characters',
      'changeAuthorLinks': 'Author app links added: Ataraxy and MSoc',
      'changePrev1': 'Habit, task and alarm refinements',
      'changePrev2': 'PIN lock added',
      'changePrev3': 'Data export / import',
      'changePrev4': 'Nutrition module with 7-day history',
      'motivationQuote1': 'An easy life begins with a simple “enough”.',
      'motivationQuote2': 'You don’t have to fit everything in — a lot can simply be let go.',
      'motivationQuote3': 'Breathe deeper: hurry doesn’t speed things up, it only tires you.',
      'motivationQuote4': 'A small step without strain lasts longer than a sprint.',
      'motivationQuote5': 'Let yourself rest without earning it first.',
      'motivationQuote6': 'A simple morning makes the whole day lighter.',
      'motivationQuote7': 'You don’t need to be the best — being real is enough.',
      'motivationQuote8': 'Let go of what isn’t in your hands, and breathing gets easier.',
      'motivationQuote9': 'Silence isn’t emptiness — it’s room for yourself.',
      'motivationQuote10': 'Do less, but more calmly.',
      'motivationQuote11': 'Ease isn’t laziness — it’s the right rhythm.',
      'motivationQuote12': 'One kind deed is enough for today.',
      'motivationQuote13': 'Don’t compare your path to someone else’s: everyone has their own pace.',
      'motivationQuote14': 'Allow yourself not to know every answer.',
      'motivationQuote15': 'A calm mind solves things faster than a tired one.',
      'motivationQuote16': 'Clear away the extra, and life gets roomier.',
      'motivationQuote17': 'Tell yourself “I’m managing”, and it gets easier.',
      'motivationQuote18': 'Rest is part of the work, not a reward for it.',
      'motivationQuote19': 'Gentleness with yourself is stronger than strictness.',
      'motivationQuote20': 'Don’t race the day — live it.',
      'motivationQuote21': 'Just because it’s easy doesn’t mean it’s wrong.',
      'motivationQuote22': 'Start small and don’t rush the ending.',
      'motivationQuote23': 'Your worth doesn’t depend on your speed.',
      'motivationQuote24': 'Leave one worry behind today.',
      'motivationQuote25': 'Live so that in the evening you want to exhale with a smile.',
      'motivationQuote26': 'Simplicity is the most underrated luxury.',
      'motivationQuote27': 'Don’t drag yesterday into a new day.',
      'motivationQuote28': 'A smile is the shortest path to lightness.',
      'motivationQuote29': 'Allow yourself a slow day without guilt.',
      'motivationQuote30': 'It’s good where you’re not rushing.',
      'motivationQuote31': 'One breath is already a small pause.',
      'motivationQuote32': 'Do what gives you strength back.',
      'motivationQuote33': 'Not every thought needs to be finished.',
      'motivationQuote34': 'Ease is born from an honest “no”.',
      'motivationQuote35': 'You have the right to a calm evening.',
      'motivationQuote36': 'Less hustle — more life.',
      'motivationQuote37': 'A mistake is just a turn, not a failure.',
      'motivationQuote38': 'Be as kind to yourself as you are to a friend.',
      'motivationQuote39': 'Your rhythm is right if you feel good in it.',
      'motivationQuote40': 'Morning begins not with tasks, but with breathing.',
      'motivationQuote41': 'Don’t fill every minute — leave room for wonder.',
      'motivationQuote42': 'Ease is when you have nothing to prove.',
      'motivationQuote43': 'Let the day be ordinary.',
      'motivationQuote44': 'A quiet “all is well” is worth loud victories.',
      'motivationQuote45': 'Rest before you want to, not after you collapse.',
      'motivationQuote46': 'A clear desk, a clear head.',
      'motivationQuote47': 'Let go of control where it only tires you.',
      'motivationQuote48': 'Look at the sky at least once a day.',
      'motivationQuote49': 'Less screen — more air.',
      'motivationQuote50': 'A walk without a goal heals better than plans.',
      'motivationQuote51': 'Thank your body for carrying you.',
      'motivationQuote52': 'You don’t have to be productive every minute.',
      'motivationQuote53': 'Boredom is sometimes rest for the soul.',
      'motivationQuote54': 'Drink water, breathe, live now.',
      'motivationQuote55': 'Don’t postpone joy to “someday”.',
      'motivationQuote56': 'Do something today just for pleasure.',
      'motivationQuote57': 'A quiet evening beats a noisy race.',
      'motivationQuote58': 'Let yourself dream without a plan.',
      'motivationQuote59': 'Warmth around you starts with warmth inside.',
      'motivationQuote60': 'One thing at a time — and the world won’t collapse.',
      'motivationQuote61': 'Tired? Rest, don’t quit.',
      'motivationQuote62': 'Don’t demand more of yourself than of others.',
      'motivationQuote63': 'Joy lives in small things, if you notice them.',
      'motivationQuote64': 'Slower means more attentive.',
      'motivationQuote65': 'Forgive yourself for yesterday’s tiredness.',
      'motivationQuote66': 'An easy life is a choice, not luck.',
      'motivationQuote67': 'Start the day with gratitude, not anxiety.',
      'motivationQuote68': 'Home is where you feel calm.',
      'motivationQuote69': 'Don’t chase everything — choose what’s yours.',
      'motivationQuote70': 'Silence over a cup of tea is a conversation too.',
      'motivationQuote71': 'Let go of others’ expectations — they aren’t yours.',
      'motivationQuote72': 'Good sleep is half of an easy life.',
      'motivationQuote73': 'Live so you don’t want to run from yourself.',
      'motivationQuote74': 'Leave room in the day for nothing.',
      'motivationQuote75': 'A simple “no” frees up a whole evening.',
      'motivationQuote76': 'Don’t compare your beginning to someone’s middle.',
      'motivationQuote77': 'Ease is trust in yourself.',
      'motivationQuote78': 'Take a step, not a leap.',
      'motivationQuote79': 'Smile for no reason — a reason will turn up.',
      'motivationQuote80': 'You don’t have to get everything done today.',
      'motivationQuote81': 'The day gets kinder when you don’t rush it.',
      'motivationQuote82': 'Tenderness with yourself isn’t weakness.',
      'motivationQuote83': 'Less noise, more meaning.',
      'motivationQuote84': 'Live now — the past has already had its rest.',
      'motivationQuote85': 'Let good things come without effort.',
      'motivationQuote86': 'Rest is movement forward too.',
      'motivationQuote87': 'Your calm matters more than others’ opinions.',
      'motivationQuote88': 'Every breath is a new chance to begin gently.',
      'motivationQuote89': 'An easy life begins with an easy gaze.',
      'motivationQuote90': 'You are already enough. Just be.',
      'areYouSure': 'Are you sure?',
      'streakResetDone': 'Streak reset',
      'openSettings': 'Open settings',
      'italic': 'Italic',
      'berserkCardTitle': 'MAXIMUM BERSERK LEVEL UPGRADE',
      'berserkCardSubtitle':
          'Hold the “+” on any screen — a mode of personal power and focus opens.',
      'taskNotesTitle': 'I remembered what I use it for…',
      'taskNotesSubtitle':
          'Hold a task for 5 seconds — a quick note up to 150 characters, kept right on the task.',
      'taskNoteSheetTitle': 'I remembered what I use it for…',
      'taskNoteSheetSubtitle':
          'Write a short note up to 150 characters — it stays on the task.',
      'taskNoteHint': 'Why do I keep this task? What is it for?',
      'clearNote': 'Clear',
      'taskNoteCleared': 'Note cleared',
      'taskNoteSaved': 'Note saved',
      'berserkTitle': 'MAXIMUM BERSERK\nLEVEL UPGRADE',
      'berserkSubtitle':
          'A short power mode: focus, composure, action. Hold the “+” anywhere — and it opens.',
      'berserkPracticeTitle': 'Practice from AGI — today’s steps',
      'berserkMotto': 'Do it quietly. Do it today.',
      'berserkPrinciple1':
          '💵 Get rich not from motivational promises, but from the skill you sell and the work you finish.',
      'berserkPrinciple2':
          '🗿 Keep your posture, clear eyes and sharp cheekbones through sleep, movement, water and self-care.',
      'berserkPrinciple3':
          '🛡️ Notice manipulation: pause, a clarifying question, a calm “no” — without excuses or guilt.',
      'berserkPrinciple4':
          '🔥 Close one expensive step every day, even if it is small and imperfect.',
      'berserkPrinciple5':
          '⚔️ Choose boundaries and self-respect over impulsive reactions or the need to please everyone.',
      'berserkPrinciple6':
          '🧠 Train attention: one block without the phone, one task, one measurable result.',
      'berserkPrinciple7':
          '📈 Turn mistakes into data: wrote it down, understood the cause, changed the action, repeated.',
      'berserkPrinciple8':
          '👑 Speak precisely: what you need, by when, and what the next step is.',
      // New Year 2027 event: one santa hat gifted every day
      'nyEventTitle': 'A hat every day',
      'nyEventBody': 'Day {0} of 12 · Hats collected: {1}',
      'nyEventFinalDay': 'Happy New Year! All 12 hats collected!',
      'nyMarkBtn': 'Claim',
      'nyMarkedBtn': 'Received',
      'nyGiftHint': 'Day 12 unlocks a gift: the Polar set',
      'nyPrizeDone':
          'Gift opened: the Metel theme, the keyhole skin, 60 days of food '
          'history and 30 categories',
      'nyPrizeGiven': 'Gift opened: the Polar set',
      'nyPrizeTheme': 'New theme available: Metel',
      'nyPrizeReverted': 'The gift is gone: theme Metel turned off',
      'nySaveFailed': 'Could not save — the hat stayed on the shelf',
      'nyResetTitle': 'Reset the whole event?',
      'nyResetBody': 'All collected hats will disappear for good.',
      'nyResetConfirm': 'Reset',
    },

    'ru': {
      'alarms': 'Будильники',
      'habits': 'Привычки',
      'tasks': 'Задачи',
      'rc': 'РП',
      'realityChecks': 'Проверки реальности',
      'settings': 'Настройки',
      'statistics': 'Статистика',
      'nutrition': 'Питание',
      'calories': 'Калории',
      'meals': 'Приёмы пищи',
      'timers': 'Таймеры',
      'categories': 'Категории',
      'category': 'Категория',
      'all': 'Все',
      'uncategorized': 'Без категории',
      'newCategory': 'Новая категория',
      'categoryName': 'Название категории',
      'manageCategories': 'Управление категориями',
      'categoryExists': 'Категория уже существует',
      'createCategory': 'Создать',
      'deleteCategory': 'Удалить категорию',
      'deleteMealConfirmTitle': 'Удалить приём пищи?',
      'deleteMealConfirmBody':
          'Этот приём пищи будет удалён. Действие нельзя отменить.',
      'deleteMealConfirm': 'Удалить приём пищи',
      'profile': 'Профиль',
      'profileAnonymous': 'Аноним',
      'profileName': 'Короткое имя',
      'profileNameHint': 'Как вас звать?',
      'profileNameSaved': 'Имя сохранено',
      'profileOnlineTitle': 'Онлайн-статус',
      'profileOnlineSwitch': 'Показывать красный кружок',
      'profileOnlineSwitchDesc': 'Другие увидят, что вы на связи',
      'profileMusic': 'Твоя музыка',
      'profileMusicTrack': 'Мой трек',
      'profileMusicEmpty': 'Добавьте свой трек — он будет играть в профиле',
      'profileMusicAdd': 'Выбрать файл',
      'profileMusicChange': 'Заменить',
      'profileMusicSet': 'Музыка сохранена',
      'profileMusicFailed': 'Не удалось загрузить музыку',
      'profileMusicMissing': 'Файл не найден',
      'profileMusicPlaying': 'Играет бодрый звук',
      'profileMusicPaused': 'Пауза',
      'profileLeaderboard': 'Рейтинг',
      'profileAddFriend': 'Добавить друга',
      'profileNoFriends': 'Добавьте друзей, чтобы сравнивать прогресс',
      'profileFriendsFull': 'В рейтинге уже 50 друзей',
      'profileFriendName': 'Имя друга',
      'profileFriendScore': 'Очки рейтинга',
      'profileFriendScoreRandom': 'Случайные очки',
      'profileFriendScoreHint':
          'Очки — за активность: привычки, задачи, дни в логе. '
              'Чем больше — тем выше в рейтинге.',
      'profileFriendSetScore': 'Очки',
      'profilePickAvatar': 'Аватарка',
      'profileAvatarFromGallery': 'Своя из галереи',
      'profileAvatarSet': 'Аватарка обновлена',
      'profileAvatarFailed': 'Не удалось загрузить аватарку',
      'profileMe': 'Я',
      'profileEvents': 'События',
      'eventNewYear': 'Новогодний ивент',
      'eventNewYearDesc': 'Каждый день — новая шапка до 1 января',
      'eventNewYearSoon': 'Ивент ещё не начался',
      'eventCeramics': 'Керамическая ярмарка',
      'eventCeramicsDesc': 'Мастер-классы и обжиг для новичков',
      'eventCommunity': 'Встреча сообщества',
      'eventCommunityDesc': 'Онлайн-сбор керамика-юзеров раз в месяц',
      'about': 'О приложении',
      'dataStorageError':
          'Не удалось прочитать или сохранить локальные данные. Исходные файлы не изменены.',
      'updateHashMissing':
          'У релиза нет корректного SHA-256. Установка отменена.',
      'updateInstalled': 'Обновлено до v{v}',
      'updateAvailable': 'Доступно обновление',
      'updateAvailableBody': 'Установить v{v}?',
      'install': 'Установить',
      'updateInstallBlocked':
          'Система заблокировала обновление. Разрешите установку из этого источника и попробуйте снова.',
      'updateInstallCancelled': 'Обновление отменено',
      'open': 'Открыть',
      'patchNotes': 'Список изменений',
      'soon': 'Скоро',
      'noAlarms': 'Будильников пока нет',
      'noHabits': 'Привычек пока нет',
      'noTasks': 'Задач пока нет',
      'noRealityChecks': 'Проверок реальности пока нет',
      'emptyAlarmHint':
          'Настрой мягкий ритм дня — первый будильник займёт минуту.',
      'emptyAlarmAdvice':
          'Начни с одного надёжного времени подъёма. Звук и сценарий можно настроить позже.',
      'emptyHabitHint': 'Дай одному небольшому действию место в своём дне.',
      'emptyHabitAdvice':
          'Привычка становится сильнее, когда её легко повторить даже в обычный день.',
      'emptyTaskHint':
          'Держи следующий важный шаг перед глазами — и его будет проще завершить.',
      'emptyTaskAdvice':
          'Формулируй задачу как одно ясное действие. Маленькие победы создают темп.',
      'emptyRealityHint':
          'Преврати обычный момент в короткую паузу осознанности.',
      'emptyRealityAdvice':
          'Выбери вопрос, который тебе действительно захочется вспомнить в течение дня.',
      'noTimers': 'Таймеров пока нет',
      'noMeals': 'Приёмов пищи пока нет',
      'theme': 'Тема',
      'language': 'Язык',
      'light': 'Светлая',
      'dark': 'Тёмная',
      'system': 'Сист.',
      'themeSystemLight': 'Сист. свет.',
      'peach': 'Персик',
      'grok': 'Grok',
      'rose':
          'Rose', // Название темы Rose на русском — должно быть "Rose" как в англ.
      'metel': 'Метель', // Подарочная тема: имя русское, не переводим
      'followSystem': 'Язык системы',
      'english': 'Английский',
      'russian': 'Русский',
      'french': 'Французский',
      'data': 'Данные',
      'export': 'Экспорт',
      'import': 'Импорт',
      'exportDone': 'Настройки экспортированы',
      'importDone': 'Настройки импортированы',
      'importError': 'Не удалось импортировать',
      'importWrongFile': 'Выберите файл .json',
      'license': 'Лицензия: MIT',
      'madeWithLove': 'Сделано с',
      'refresh': 'Обновить',
      'save': 'Сохранить',
      'cancel': 'Отмена',
      'delete': 'Удалить',
      'undo': 'Отменить',
      'soundDeleted': 'Звук удалён',
      'ok': 'ОК',
      'back': 'Назад',
      'clear': 'Очистить',
      'done': 'Готово',
      'add': 'Добавить',
      'newAlarm': 'Новый будильник',
      'editAlarm': 'Изменить будильник',
      'tapToChange': 'Нажмите, чтобы изменить',
      'repeat': 'Повтор',
      'wakeUpTask': 'Задача пробуждения',
      'taskNone': 'Нет',
      'taskMath': 'Решить пример',
      'taskPattern': 'Запомнить паттерн',
      'taskMemory': 'Игра на память',
      'label': 'Название',
      'vibrate': 'Вибрация',
      'sound': 'Звук',
      'customSound': 'Свой',
      'pin': 'Закрепить',
      'pinMsg': 'Закреплено',
      'unpinMsg': 'Откреплено',
      'pinMeal': 'Закрепить',
      'unpinMeal': 'Открепить',
      'renameSound': 'Переименовать звук',
      'soundName': 'Название звука',
      'soundRenamed': 'Звук переименован',
      'soundRenameFailed': 'Не удалось переименовать звук',
      'labelOnce': 'Однократно',
      'labelEveryDay': 'Каждый день',
      'labelWeekdays': 'Будни',
      'labelWeekends': 'Выходные',
      'dayMon': 'Пн',
      'dayTue': 'Вт',
      'dayWed': 'Ср',
      'dayThu': 'Чт',
      'dayFri': 'Пт',
      'daySat': 'Сб',
      'daySun': 'Вс',
      'alarmNoExact':
          'Точные будильники не разрешены. Перейди в Настройки → Приложения → Agysha → Батарея → Без ограничений',
      'pinLock': 'PIN-код',
      'pinDescription': 'Поставьте PIN, чтобы заблокировать приложение',
      'setPin': 'Поставить PIN',
      'changePin': 'Сменить PIN',
      'removePin': 'Убрать PIN',
      'enterPin': 'Введите PIN',
      'confirmPin': 'Подтвердите PIN',
      'wrongPin': 'Неверный PIN',
      'pinsDoNotMatch': 'PIN-коды не совпадают',
      'exit': 'Выйти',
      'exitConfirmTitle': 'Ты точно хочешь принять зелёную таблетку?',
      'exitConfirmBody': 'Кнопка «Выйти» закроет приложение.',
      'newHabit': 'Новая привычка',
      'editHabit': 'Редактировать привычку',
      'habitName': 'Название привычки',
      'streak': 'дней подряд',
      'habitType': 'Тип',
      'habitTypeGood': 'Полезная',
      'habitTypeBad': 'Вредная',
      'habitDays': 'Дни недели',
      'remindAll': 'Вспомнить всё',
      'remindAt': 'Напоминать в',
      'remindOffHint': 'Напомнит о привычке в выбранное время',
      'remindOnHint': 'Каждый день или по выбранным дням',
      'remindCustomText': 'Текст напоминания (до 60 симв.)',
      'remindCustomHint': 'Например: Пора пить воду',
      'habitDaysHint': 'Пусто = каждый день',
      'everyDay': 'Каждый день',
      'habitNotesBtn': 'Статус',
      'habitStatusTitle': 'Напоминание',
      'habitStatusHint': 'Короткая напоминалка',
      'habitNotesTitle': 'Что нужно запомнить',
      'habitNotesHint': 'Запиши, что важно',
      'habitPinOnlyGood': 'Закрепить можно только полезную привычку',
      'habitPinned': 'Привычка закреплена',
      'habitUnpinned': 'Привычка откреплена',
      'habitsSectionGood': 'Полезные',
      'habitsSectionBad': 'Вредные',
      'tasksSectionDone': 'Архивные',
      'newTask': 'Новая задача',
      'editTask': 'Редактировать задачу',
      'taskTitle': 'Название задачи',
      'completed': 'Выполнено',
      'description': 'Описание',
      'notes': 'Заметки',
      'priority': 'Приоритет',
      'priorityLow': 'Низкий',
      'priorityMedium': 'Средний',
      'priorityHigh': 'Высокий',
      'dueDate': 'Срок',
      'dueNone': 'Без срока',
      'dueToday': 'Сегодня',
      'dueTomorrow': 'Завтра',
      'dueIn3Days': 'Через 3 дня',
      'dueInWeek': 'Через неделю',
      'duePickDate': 'Выбрать дату',
      'estimate': 'За сколько',
      'estimateNone': 'Без лимита',
      'overdue': 'Просрочено',
      'dragToReorder': 'Перетащи, чтобы изменить порядок',
      'overallCompletion': 'Общий прогресс',
      'doneToday': 'Сделано',
      'refreshed': 'Обновлено',
      'newRc': 'Новая проверка',
      'editRc': 'Изменить проверку',
      'rcQuestion': 'Что спросить себя?',
      'rcDone': 'Проверка реальности выполнена!',
      'rcToday': 'сегодня',
      'rcChecks': 'всего проверок',
      'rcStat': 'Проверки реальности',
      'monthChartTitle': 'Последние 30 дней',
      'monthChartHabits': 'Привычки',
      'monthChartTasks': 'Задачи',
      'monthChartBest': 'лучший день',
      'monthChartHint': 'Каждый столбик — один день. Его высота — сколько выполнено: снизу привычки, сверху задачи. Колонка «сегодня» подсвечена, звезда — лучший день.',
      'monthChartDays': 'дней выполнено',
      'rcReset': 'Сбросить статистику',
      'rcResetBody': 'Сбросить все счётчики проверок в ноль?',
      'rcExit': 'Выход',
      'disableRcTitle': 'Выключить проверки реальности?',
      'disableRcBody':
          'Раздел свернётся и появится таблетка-переключатель. Проверки перестанут учитываться в общей статистике.',
      'disableRcLongHint': 'Долгое нажатие на заголовок — выключить',
      'disable': 'Выключить',
      // Карточка в Настройках -- выключатель всего раздела РП.
      'rcSettingsTitle': 'Проверки реальности',
      'rcSettingsBody':
          'Убирает или добавляет раздел целиком: таб «РП» в Home, расписание и уведомления.',
      'rcSettingsOn': 'Раздел «Проверки реальности» включён',
      'rcSettingsOff': 'Раздел «Проверки реальности» скрыт',
      'rcChecksPerDay': 'Проверок в день',
      'rcTimeRange': 'Временной диапазон',
      'rcFrom': 'С',
      'rcTo': 'До',
      'rcScheduled': 'по расписанию',
      'rcText1': 'Это сон?',
      'rcText2': 'Посмотри на свои руки. Можешь пересчитать пальцы?',
      'rcText3': 'Попробуй просунуть палец сквозь ладонь.',
      'rcText4': 'Прочитай это предложение дважды. Текст не изменился?',
      'rcText5': 'Осмотрись — ты точно знаешь это место?',
      'rcText6': 'Что ты делал десять минут назад? Это было по-настоящему?',
      'rcText7': 'Потрогай ближайшую стену. Текстура натуральная?',
      'rcText8': 'Скажи своё имя вслух. Это звучит как ты?',
      'perfectionism': 'Борьба с перфекционизмом',
      'perfectionismHint': 'Ежедневная подборка против перфекционизма',
      'perfTitle1': 'ОКР',
      'perfTitle2': 'Несовершенство',
      'perfTitle3': 'Ступор',
      'perfTitle4': 'Всё или ничего',
      'perfTitle5': 'Прокрастинация',
      'perfTitle6': 'Самокритика',
      'perfTitle7': 'Мысленные ритуалы',
      'perfTitle8': 'Непереносимость',
      'perfTitle9': 'Гиперконтроль',
      'perfTitle10': 'Покой — не лень',
      'perfTitle11': 'Цикл стыда',
      'perfTitle12': 'Сканирование',
      'perfTitle13': 'Заземление',
      'perfTitle14': 'Сигнал тела',
      'perfTitle15': 'Ловушка идей',
      'perfTitle16': 'Саморазвитие как ритуал',
      'perfTitle17': 'Баланс',
      'perfTitle18': 'Исследование',
      'perfTitle19': 'Рост через хаос',
      'perfTitle20': 'Вещи рассказывают истории',
      'perf1Short': 'Разреши беспорядок.',
      'perf2Short': 'Микрошаг сильнее ступора.',
      'perf3Short': 'Маленькое сегодня лучше большого плана.',
      'perf4Short': 'Сделанного достаточно. Идеал — враг.',
      'perf5Short': 'Прокрастинация — это страх, не лень.',
      'perf6Short': 'Слова — не приговор.',
      'perf7Short': 'Назови петлю и оборви её.',
      'perf8Short': 'Неопределённость — не опасность.',
      'perf9Short': 'Отпусти, чтобы взять контроль.',
      'perf10Short': 'Пауза — не неудача.',
      'perf11Short': 'Стыд тебя не строит.',
      'perf12Short': 'Не ищи проблемы — живи.',
      'perf13Short': 'Почувствуй стопы — ты здесь.',
      'perf14Short': 'Тело сигналит правду.',
      'perf15Short': 'Мыслить — не делать.',
      'perf16Short': 'Не всякое улучшение — прогресс.',
      'perf17Short': 'Стабильность важнее интенсивности.',
      'perf18Short': 'Любопытство — путь наружу.',
      'perf19Short': 'Грязь — часть искусства.',
      'perf20Short': 'Всё вокруг выбрано.',
      'perf1Full':
          'Беспорядок — не враг.\nКривая полка всё равно полка.\nСделанное бьёт идеальное.\nПрогресс важнее совершенства.',
      'perf2Full':
          'Неидеально — тоже прекрасно.\nНегатив — часть работы, а не приговор.\nЗакрой глаза, сделай маленький шаг и продолжай.\nТы не обязан быть идеальным, чтобы идти вперёд.',
      'perf3Full':
          'Ступор — это сигнал, а не стена.\nСделай микро-шаг: одна строка, один клик.\nДвижение убивает страх.\nСейчас самое время сделать что-то маленькое.',
      'perf4Full':
          'Сделанного достаточно.\nИдеал — враг хорошего.\nНачни коряво. Отполируешь потом.\nДвижение бьёт перфекционизм.',
      'perf5Full':
          'Прокрастинация — страх перед результатом, не лень.\nНачни на 2 минуты — тело захочет продолжить.\nДействие сжигает тревогу.\nЛюбое начало бьёт страх.',
      'perf6Full':
          'Ты уже делаешь. Самокритика не ускоряет рост.\nБудь к себе тем, кем был бы к другу.\nУбавь громкость внутреннего критика.\nМягкость даёт больше, чем крик.',
      'perf7Full':
          'Ум крутит одну и ту же мысль.\nНазови её: «это ОКР» — и отвернись.\nНе решай — наблюдай.\nКаждое возвращение слабее прошлого.',
      'perf8Full':
          'Потребность знать всё — ловушка.\nЖиви вопросом.\nТерпи незнание.\nОпределённость — фантазия; смелость — реальна.',
      'perf9Full':
          'Затягивание каждого винта выматывает.\nОслабь хватку.\nДелай меньше, но честно.\nСвобода живёт в зазоре между стимулом и реакцией.',
      'perf10Full':
          'Отдых — не сдача.\nПауза может быть самым продуктивным.\nПосиди с ней. Подыши. Вернёшься, когда будешь готов.',
      'perf11Full':
          'Циклы стыда замораживают.\nНазови его — он смягчится.\nТы всё ещё в пути.',
      'perf12Full':
          'Перестань разглядывать мир под лупой.\nИзъяны, которые ты ищешь, не видит никто кроме тебя.\nОпасности нет — есть тревожный фокус.\nШире окно — тише внутри.',
      'perf13Full':
          'Когда мысли скачут, прижми стопы к полу.\nХолодный воздух. Тихий звук.\nПять вещей, которые видишь прямо сейчас.\nЭтого момента достаточно.',
      'perf14Full':
          'Тело говорит честнее мыслей.\nТревога сжимает плечи, страх — живот.\nПрежде чем думать — послушай.\nОно знает первым и не врёт.',
      'perf15Full':
          'Идеальный план в голове ничего не стоит.\nНапиши одну плохую фразу. Сделай один неловкий шаг.\nДелание бьёт планирование — каждый раз.',
      'perf16Full':
          'Сбор советов, чтение рекомендаций, тюнинг ритуалов — тоже могут стать ритуалом.\nСпроси: я сегодня что-то реально сделал?',
      'perf17Full':
          'Маленькие ежедневные действия бьют героические рывки.\nМинута дыхания > час прокрастинации.\nВыбирай путь, который длится.',
      'perf18Full':
          'Любопытство — антидот перфекционизма.\nСпроси: что будет, если попробовать иначе?\nОшибка — это разведка, не провал.\nПуть интереснее результата.',
      'perf19Full':
          'Несовершенство оставляет следы, которые доказывают: ты был здесь.\nЧистая поверхность прячет руку мастера.\nТвой беспорядок имеет ценность.',
      'perf20Full':
          'Посмотри на пять предметов в комнате.\nКаждый сделал тот, кто боролся, адаптировался и пробовал снова.\nТы часть этой цепи.',
      'wtTest': 'Проверить задачу',
      'wtSolved': 'Отлично! Ты проснулся!',
      'wtDismiss': 'Отключить будильник',
      'wtWrong': 'Неверно! Попробуй ещё раз.',
      'wtMathTitle': 'Реши пример, чтобы отключить будильник',
      'wtAnswerHint': 'Введите ответ',
      'wtCheck': 'Проверить',
      'wtPatternTitle': 'Запомни последовательность и нажми',
      'wtPatternWatch': 'Смотри внимательно',
      'wtMemoryTitle': 'Запомни числа и введи их',
      'overthinking': 'Прокручивание мыслей',
      'procrastination': 'Прокрастинация',
      'selfCriticism': 'Самокритика',
      'notifications': 'Уведомления',
      'notificationsDesc': 'Включить или отключить все уведомления',
      'batteryOptimization': 'Оптимизация батареи',
      'batteryOptDesc': 'Отключите для надёжной работы будильников',
      'batteryOpened': 'Настройки батареи открыты',
      'batterySettings': 'Настройки батареи',
      'batterySettingsDesc': 'Отключите оптимизацию для стабильных будильников',
      'fullscreenNotif': 'Полноэкранные уведомления',
      'fullscreenNotifDesc': 'Показывать будильник поверх экрана блокировки',
      'fullScreenNotifTitle': 'Полноэкранные уведомления',
      'fullScreenNotifBody':
          'Нужно, чтобы будильник показывался поверх экрана блокировки',
      'fullScreenGrantMissing':
          'Система отключила полноэкранный показ. Будильник всё равно откроет экран задачи, но право надёжнее вернуть.',
      'autostart': 'Автозапуск',
      'autostartDesc':
          'Разрешить будильнику срабатывать, когда приложение закрыто',
      'popupWarningTitle': 'Важно!',
      'popupWarningBody':
          'Чтобы будильники срабатывали надёжно, разреши уведомления и полноэкранный режим.',
      'popupWarningOpen': 'Открыть настройки',
      'popupWarningDismiss': 'Позже',
      'dontShowAgain': 'Не показывать снова',
      'settingsCantOpen':
          'Не удалось открыть настройки. Откройте настройки приложения → Уведомления / Батарея вручную.',
      'welcomeTitle': 'Добро пожаловать в Agysha!',
      'welcomeBody':
          'Важно для точной работы будильников: разрешите уведомления и работу приложения в фоне без ограничений. Настройки можно открыть сейчас или позже.',
      'welcomeGo': 'К настройкам',
      'welcomeSkip': 'Пропустить',
      'maxAlarms': 'Максимум 10 будильников',
      'maxHabits': 'Максимум 100 привычек',
      'maxTasks': 'Максимум 150 задач',
      'maxRc': 'Максимум 1 проверка',
      'maxTimers': 'Максимум 5 таймеров',
      'maxCat': 'Максимум {n} категорий',
      'maxCal': 'Максимум 10000 ккал',
      'maxCalPerMeal': 'Максимум 10000 ккал за приём',
      'fillAllFields': 'Пожалуйста, заполните все поля',
      'mealAdded': 'Приём пищи успешно добавлен',
      'kcalShort': 'ккал',
      'mlShort': 'мл',
      'water': 'Вода',
      'waterField': 'Вода, мл',
      'calorieNorm': 'Дневной лимит',
      'ofPrefix': 'из',
      'normSaved': 'Норма сохранена',
      'mealsToday': 'Приёмов сегодня',
      'macroP': 'Белки',
      'macroF': 'Жиры',
      'macroC': 'Углеводы',
      'macroPSingle': 'Б',
      'macroFSingle': 'Ж',
      'macroCSingle': 'У',
      'trends': 'Тренды',
      'trendsWindow': 'за {n} дней',
      'avgPerDay': 'Среднее в день',
      'daysOnTarget': 'дней в норме',
      'bestDay': 'лучший день',
      'maxWaterPerMeal': 'Максимум 3000 мл за приём',
      'needNameOrWater': 'Укажите блюдо или воду',
      'maxDigitsHit': 'Дальше нельзя',
      'clearAll': 'Очистить',
      'backspace': 'Стереть',
      'diagnostics': 'Диагностика',
      'diagAlarmTest': 'Тест уведомления будильника',
      'testAlarm': 'Тест будильника',
      'diagRcTest': 'Тест уведомления проверки',
      'diagSoundTest': 'Тест звука',
      'diagSent': 'Уведомление отправлено!',
      'diagSoundPlayed': 'Звук сыгран!',
      'diagNotEnabled': 'Уведомления отключены',
      'diagEnableNotif':
          'Уведомления выключены — откройте настройки, чтобы включить их.',
      'diagError': 'Ошибка',
      'resetWarnings': 'Сбросить предупреждения',
      'warningsResetDone': 'Предупреждения сброшены — появятся снова',
      'mildImprovements': 'Небольшие улучшения',
      'experimentalSettings': 'Экспериментальное',
      'experimentalDesc': 'Показ секции таймеров (таймеры сохраняются)',
      'aiGuide': 'Ада',
      'aiGuideSub': 'Тренер привычек',
      'adaName': 'Ада',
      'adaTagline': 'ничего не надо',
      'aiClear': 'Очистить чат',
      'aiUndo': 'Отменить',
      'aiWindow': 'Свернуть в окно',
      'aiWindowOff': 'Выключить окно',
      'aiWindowHint': 'Свёрнуто в мини-окошко — тяни пальцем, тап вернёт чат',
      'aiSystemWindowHint':
          'Ада теперь в мини-окошке поверх других приложений — закрой его там',
      'aiOverlayPermissionHint':
          'Разреши Agysha показывать поверх других приложений, чтобы включить мини-окошко',
      'aiOverlayEmpty': 'Поболтай с Адой',
      'aiInputHint': 'Сообщение…',
      'pinLimit': 'Можно закрепить до 10 сообщений',
      'adaTracking': 'Ада-трекинг',
      'adaTrackingDesc':
          'Ада сама пишет утренний отчёт «что сегодня по плану» в 08:00 и вечерний разбор в 21:00 прямо в чат — уведомления не нужны.',
      'adaTrackingOn':
          'Ада теперь сама пишет в чат каждый день в 08:00 и 21:00',
      'adaQuota': 'Ада: осталось N бесплатных сегодня',
      'aiChipHabit': 'Привычка',
      'aiChipTask': 'Задача',
      'aiChipAlarm': 'Будильник',
      'aiChipRC': 'Проверка',
      'aiChipMeal': 'Еда',
      'aiWebSearch': 'Веб-поиск',
      'aiWebSearchOn': 'Веб-поиск ВКЛ',
      'adaEmptyChat': 'Ада проложит путь ―\nлибо туда, либо туда',
      'readReceipt': 'Прочитано',
      'readReceiptAt': 'Прочитано в',
      'aiGuideHint': 'Спроси меня',
      'aiComposing': 'Сочиняю',
      'aiEmptyAnswer': 'Хм, я не смогла собрать ответ. Попробуй ещё раз!',
      'share': 'Поделиться',
      'aiGuideToggle': 'Включить проводника',
      'aiGuideDesc':
          'Рядом с кнопкой «+» появится мелкий кружок — он открывает мини-чат.',
      'aiGuideKey': 'Ключ Poolside (необязательно)',
      'aiGuideKeyHint': 'Вставь свой ключ Laguna',
      'aiGuideKeyNote':
          'Бесплатные провайдеры: Kilo, OVHcloud, Murakumo и AI Horde. Ключ Poolside необязателен.',
      'aiGuideKeyNoteProviders': 'Kilo, OVHcloud, Murakumo и AI Horde',
      'aiGuideKeyNoteTail': '',
      'geminiKey': 'Ключ Gemini (необязательно — самая живая и горячая Ада)',
      'geminiKeyHint': 'Вставь ключ из Google AI Studio',
      'freeFallbacks': 'Бесплатные фолбэки:',
      'aiResort': 'ИИ на курорте, подожди немного',
      'retry': 'Повторить',
      'changeIcon': 'Сменить иконку',
      'chooseIcon': 'Выберите иконку',
      'timeMode': 'Режим времени',
      'addTime': 'Добавить время',
      'today': 'Сегодня',
      'yesterday': 'Вчера',
      'todayErased': 'Сегодня очищено',
      'changelogTitle': 'Что нового',
      'dailyMotivation': 'Мотивация дня',
      'addMeal': 'Добавить приём',
      'tipSugarTitle': 'Щит от сахара',
      'tipSugarBody':
          'Если сладкое в упаковке — оно хочет остаться в магазине. Выбирай фрукт, горький шоколад или воду.',
      'tipSugarBody2':
          'Белок дольше сохраняет сытость. Добавь яйцо, йогурт или орехи к каждому приёму пищи — и перекусывать почти не тянет.',
      'tipWaterTitle': 'Сначала вода',
      'tipWaterBody':
          'Часто жажда маскируется под голод. Выпей стакан воды и подожди 10 минут, прежде чем добавки.',
      'tipProteinTitle': 'Белковый якорь',
      'tipProteinBody':
          'Белок дольше сохраняет сытость. Добавь яйцо, йогурт или орехи к каждому приёму пищи — и перекусывать почти не тянет.',
      'tipWalkTitle': 'Прогулка',
      'tipWalkBody': '10 минут ходьбы снимают тягу быстрее, чем сила воли.',
      'tipCoffeeTitle': 'Чёрный кофе',
      'tipCoffeeBody':
          'Чашка чёрного кофе глушит тягу к сладкому на 30–40 минут.',
      'tipColdWaterTitle': 'Ледяная вода',
      'tipColdWaterBody':
          'Стакан ледяной воды мгновенно перезагружает тело и голову — холод обрывает цикл тяги.',
      'tipMindfulTitle': 'Ешь осознанно',
      'tipMindfulBody':
          'Отложи телефон и жуй медленно. Через 20 минут мозг наконец догонит желудок.',
      'tipSleepTitle': 'Сон управляет аппетитом',
      'tipSleepBody':
          'Меньше 7 часов сна взвинчивает гормоны голода. Береги режим — и ночной жор отступит.',
      'tipVeggiesTitle': 'Овощи прежде всего',
      'tipVeggiesBody':
          'Начни каждый приём пищи с овощей или салата. Клетчатка насыщает до того, как на стол попадёт тяжёлая еда.',
      'tipChewTitle': 'Считай жевание',
      'tipChewBody':
          'Попробуй жевать каждый кусок 20 раз. Это замедляет еду, улучшает пищеварение и само сокращает порцию.',
      'tipFiberTitle': 'Клетчатка бьёт голод',
      'tipFiberBody':
          'Цельные зёрна и овощи насыщают дольше, чем рафинированные углеводы.',
      'tipNoSnackTitle': 'Обходи снэковый ряд',
      'tipNoSnackBody':
          'Если ты не настолько голоден, чтобы съесть яблоко, скорее всего тебе скучно или хочется пить.',
      'tipSpicesTitle': 'Добавь специй',
      'tipSpicesBody':
          'Яркие вкусы быстрее дают сигнал сытости. Добавь зелень, перец или цитрус — и ешь медленнее.',
      'tipBreakfastTitle': 'Завтрак-якорь',
      'tipBreakfastBody':
          'Белковый старт не даёт рухнуть в середине утра и тянуться за перекусом.',
      'tipPortionTitle': 'Маленькая тарелка, та же еда',
      'tipPortionBody':
          'Визуальные подсказки морочат мозг. На маленькой тарелке ты насытишься меньшим.',
      'tipAlcoholTitle': 'Алкоголь снимает тормоза',
      'tipAlcoholBody':
          'Даже одна порция снижает самоконтроль и поднимает шансы набежать на ночной холодильник.',
      'tipMindfulHungerTitle': 'Назови свой голод',
      'tipMindfulHungerBody':
          'Спроси себя: это голод, каприз или эмоциональное «заедание»? Когда называешь — импульс слабеет.',
      'tipConsistencyTitle': 'Один ритм',
      'tipConsistencyBody':
          'Еда в одни и те же часы стабилизирует сахар. Случайные приёмы пищи путают метаболизм.',
      'tipFruitCravingTitle': 'Фрукт вместо сахара',
      'tipFruitCravingBody':
          'Яблоко или ягоды утоляют тягу к сладкому без скачка сахара.',
      'tipDarkChocolateTitle': 'Горький шоколад',
      'tipDarkChocolateBody':
          'Два квадратика 85% шоколада снимают желание без чувства вины.',
      'tipYogurtTitle': 'Йогурт с ягодами',
      'tipYogurtBody':
          'Натуральный йогурт с ягодами — десерт без стыда, который ощущается как награда.',
      'tipWarmDrinkTitle': 'Тёплый напиток',
      'tipWarmDrinkBody':
          'Тёплый напиток без сахара успокаивает тягу к сладкому.',
      'tipReplaceTitle': 'Заменяй, а не запрещай',
      'tipReplaceBody':
          'Мозг сопротивляется запретам; замены работают гораздо лучше.',
      'tipStressSugarTitle': 'Стресс — не сахар',
      'tipStressSugarBody':
          'Стресс усиливает тягу к сладкому. Лучше пройдись, чем заедать.',
      'tipWaitTitle': 'Правило 10 минут',
      'tipWaitBody':
          'Подожди 10 минут, прежде чем сдаться тяге — большинство из них проходят сами.',
      'tipOvereatTitle': 'Не ешь до отвала',
      'tipOvereatBody':
          'Остановись, когда комфортно, а не когда объелся. Мозгу нужно 20 минут, чтобы понять сытость.',
      'tipSugarSwapTitle': 'Замени сладкое',
      'tipSugarSwapBody':
          'Тянет на сладкое? Возьми фрукт, квадратик горького шоколада или чай с корицей — вкус есть, скачка сахара нет.',
      'tipSaltBloatTitle': 'Меньше соли — меньше отёков',
      'tipSaltBloatBody':
          'Солёные снеки и соусы задерживают воду. Приправляй травами, лимоном и специями — отёчность сойдёт за пару дней.',
      'tipPotassiumTitle': 'Калий против отёков',
      'tipPotassiumBody':
          'Бананы, зелень, авокадо и бобовые помогают выводить лишнюю воду. Добавляй что-то из них к каждому приёму пищи.',
      'tipWaterBloatTitle': 'Вода выводит воду',
      'tipWaterBloatBody':
          'Пьёшь мало — тело запасает жидкость. 6–8 стаканов в день — самая простая привычка против отёков.',
      'tipLateSaltTitle': 'Без соли на ночь',
      'tipLateSaltBody':
          'Солёный ужин к утру виден на лице. Вечером держи еду лёгкой и малосольной.',
      'tipMoveBloatTitle': 'Движение выгоняет воду',
      'tipMoveBloatBody':
          '20 минут ходьбы или лёгкая тренировка разгоняют лимфу — и отёчность заметно спадает.',
      'tipProcessedTitle': 'Мимо переработки',
      'tipProcessedBody':
          'Колбасы, чипсы и готовые блюда — солевые бомбы. Готовь из цельных продуктов — и отёки уйдут.',
      'tipHerbalTitle': 'Травяные чаи',
      'tipHerbalBody':
          'Одуванчик, крапива и зелёный чай мягко поддерживают почки и помогают сбросить лишнюю воду.',
      'tipSwellingCheckTitle': 'Когда к врачу',
      'tipSwellingCheckBody':
          'Если отёк держится неделями, односторонний или с болью — иди к врачу, а не «растворяй» его диетой.',
      'newTimer': 'Новый таймер',
      'editTimer': 'Изменить таймер',
      'timerDuration': 'Длительность',
      'timerLabel': 'Название',
      'timerDone': 'Таймер завершён!',
      'timerRunning': 'Идёт',
      'timerPaused': 'На паузе',
      'timerFinished': 'Завершён',
      'autoSave': 'Автосохранение',
      'autoSaveDesc': 'Сохранять данные каждую секунду',
      'autoExport': 'Автоэкспорт',
      'autoExportHourly': 'Сохранять бэкап в Загрузки/Agysha каждый час',
      'autoExportDone': 'Бэкап сохранён в Загрузки/Agysha',
      'autoExportFailed': 'Не удалось сохранить бэкап',
      'clearCache': 'Очистить кэш',
      'clearCacheDesc': 'Освободить место, занятое временными файлами',
      'clearCacheDone': 'Кэш очищен!',
      'haptics': 'Вибрация',
      'hapticsDesc': 'Короткая вибрация при нажатиях и переключениях',
      'sounds': 'Звуки',
      'soundsDesc': 'Мягкий системный щелчок на подтверждениях',
      'reduceMotion': 'Убрать анимации',
      'reduceMotionDesc': 'Выключить декоративные анимации и эффекты',
      'devMode': 'Режим разработчика',
      'devModePrompt': 'Введите код доступа, чтобы продолжить',
      'devModeInvalidCode': 'Код не подошёл. Попробуйте ещё раз.',
      'devModeUnlock': 'Открыть',
      'devToolsTitle': 'Инструменты разработчика',
      'devToolsSubtitle': 'Скрытые настройки для тонкой полировки приложения.',
      'devModeDisable': 'Выключить режим разработчика',
      'devPromptTitle': 'Что нужно изменить в приложении?',
      'devPromptDescription':
          'Записывайте сюда пожелания и задачи для доработки. Текст сохраняется автоматически и попадает в резервную копию.',
      'devPromptHint': 'Опишите нужные изменения, поведение или дизайн...',
      'devPromptSaving': 'Сохраняем…',
      'devPromptSaved': 'Сохранено на этом устройстве',
      'devPromptUnsaved': 'Есть несохранённые изменения',
      'devPromptSaveError': 'Не удалось сохранить. Нажмите «Сохранить».',
      'devPromptSave': 'Сохранить',
      'forgeTitle': 'Кузница',
      'forgeSubtitle': 'Живой чат с агентом: спроси о коде или попроси изменить.',
      'forgeTokenSection': 'ДОСТУП К GITHUB',
      'forgeTokenHint':
          'Fine-grained, Contents и Pull requests: read and write.',
      'startupDiagTitle': 'Agysha остановилась безопасно',
      'startupDiagBody':
          'Agysha не смогла завершить запуск и остановилась до отрисовки '
          'первого экрана. На диске ничего не изменилось. Можно повторить '
          'попытку или скопировать/сохранить подробности ниже.',
      'startupDiagDetailsTitle': 'Технические подробности',
      'startupDiagCopy': 'Копировать',
      'startupDiagSave': 'Сохранить лог',
      'startupDiagSaved': 'Лог сохранён:',
      'startupDiagSaveFailed': 'Не удалось сохранить лог в файл.',
      'startupDiagCopied': 'Скопировано в буфер обмена.',
      'startupDiagRetry': 'Попробовать снова',
      'startupDiagRetrying': 'Повторяем…',
      'startupDiagRetryFailed':
          'Перезапуск не удался. Ошибка ниже осталась прежней.',
      'forgeTokenCheck': 'Сохранить',
      'forgeTokenForget': 'Забыть токен',
      'forgeTokenOk': 'Токен рабочий',
      'forgeTokenInvalid': 'GitHub отклонил токен',
      'forgeTokenReadOnly': 'Нет права записи — агент не сможет коммитить',
      'forgeTokenEmpty': 'Нужен токен',
      'forgeTokenSaveFailed':
          'Не удалось сохранить токен — хранилище недоступно',
      'forgeTokenForgotten': 'Токен удалён',
      'forgeChatSection': 'ЧАТ',
      'forgeTaskHint': 'Спроси о коде или опиши, что изменить…',
      'forgeRun': 'Отправить',
      'forgeWorking': 'Работаю…',
      'forgeTaskEmpty': 'Нужна задача',
      'forgeProvider': 'бесплатный провайдер',
      'forgeLogSection': 'ЖУРНАЛ',
      'forgeDone': 'Pull request готов',
      'forgeBranch': 'Ветка',
      'forgeFiles': 'файлов изменено',
      'forgeSafetyNote':
          'На вопросы агент отвечает сразу. Правки идут в отдельную ветку и pull request — main не трогается. ИИ: встроенные бесплатные провайдеры.',
      'forgeThinking': 'Агент думает…',
      'forgeChatEmpty':
          'Спроси что-нибудь о проекте или напиши, что изменить.',
      'forgeClearChat': 'Очистить чат',
      'forgeChatCleared': 'Чат очищен',
      'forgeChanges': 'Правки',
      'forgeNoChanges': 'В этот раз правок нет',
      'showPassword': 'Показать код',
      'hidePassword': 'Скрыть код',
      'patchDeveloping': 'Как развивается приложение',
      'patchRoadmap': 'Мелкие доработки, PR в 2027',
      'changeSwipeUp': 'Свайп вверх на главном экране для обновления',
      'changeAdaGuide':
          'ИИ-проводник Ада — мини-чат, который сам создаёт привычки, задачи, будильники, проверки реальности и приёмы пищи',
      'changeSmoothAnim':
          'Плавные анимации везде: переходы разделов, настройки, карточки, переключатели',
      'changeStreakFix': 'Исправлены стрики и отметки привычек',
      'changePinBlur':
          'PIN-код теперь размывает приложение в недавних приложениях',
      'changeNotifIcon': 'Иконка уведомлений — фирменный бейдж с K',
      'changeAlarmFix':
          'Будильники: восстановлены звуки, выбор времени работает зажатием',
      'changeTaskShelvesContrast':
          'Полки задач: заголовки теперь читаются и в светлой, и в тёмной теме',
      'changeLintCleanup':
          'Прибрались внутри — приложение стало чуть надёжнее',
      'changeTaskShelves': 'Задачи разделены на полки «Активные» и «Выполненные»',
      'changeTaskMarkFinal':
          'Выполнение задачи окончательно — она переезжает на полку выполненных',
      'changeCIUpdate':
          'Выпуски выходят ровнее — переделали сборку',
      'changeCategoryDrag':
          'Категории можно перетаскивать, меняя их порядок в редакторе задачи',
      'changeCategoryReorder': 'Порядок категорий меняется плавно и запоминается',
      'changeRemindAllCircle':
          '«Вспомнить всё» теперь того же тона, что и соседние кнопки',
      'changePinSmooth': 'Экран блокировки и круг привычек анимируются плавно',
      'changeFlockEdges': 'Стая птиц мягко входит и гаснет, а не обрезается',
      'changeForgeTokenSave':
          'Кузница: токен GitHub сохраняется — кнопка оживает',
      'changeForgeAgent':
          'Кузница — полноценный чат-агент: отвечает на вопросы и правит код',
      'changeForgePr':
          'Правки агента уходят в ветку и открывают pull request на проверку',
      'changeForgeFree':
          'Кузница работает «из коробки» на встроенных бесплатных провайдерах',
      'changeForgeSection':
          'В уголке разработчика появился раздел Кузницы для правок репозитория',
      'changeForgeEntry': 'Кузница доступна из Настроек, на трёх языках',
      'changeCIMemory':
          'Сборка релиза больше не падает на раннере из-за нехватки памяти Gradle',
      'changeCISigning':
          'Секреты подписи проверяются заранее: внятная ошибка вместо падения',
      'changeAutoUpdateName':
          'Автообновление сравнивает версии по имени — работает и для split APK',
      'changeHamster': 'ХАМСТЕР: статистика, поиск и ускоренный PIN-экран',
      'changeMutilatedTheme':
          'Новая тема MUTILATED — светлая кроваво-красная с еле заметными пятнами',
      'changeElegantEgg':
          'Держи плашку MUTILATED 10 секунд — вылезет пасхалка «Вы элегантны?»',
      'changeMealConfirm': 'Подтверждение перед удалением приёма пищи',
      'changeChatScroll':
          'Чат Ады плавно держит фокус на последнем сообщении при стриме и открытии',
      'changeLangSmooth': 'Переключение языков теперь плавнее',
      'changeEmDash': 'В приложении все видимые тире стали длинными (em-dash)',
      'changeSplashFix':
          'Аватарка на сплеш больше не мигает при холодном старте',
      'aboutAuthorTitle': 'Об авторе',
      'visitellaName': 'Визителла',
      'visitellaDesc': 'Проекты, игры, новости',
      'aboutAuthorBody': 'Другие приложения того же разработчика:',
      'supportAuthorTitle': 'Поддержать автора',
      'supportAuthorBody':
          'Agysha — самостоятельный проект: без рекламы и подписок. Если приложение тебе по душе, угости автора кофе — это лучшее «спасибо».',
      'supportAuthorHint': 'Откроет страницу благодарности в браузере',
      'supportSoonToast': 'Оплата через Ozon уже на подходе — совсем скоро!',
      'supportOzonSubtitle': 'Скоро — поддержка покупкой',
      'supportBoostySubtitle': 'Разовый донат или подписка',
      'support': 'Угостить кофе',
      'rcNotificationTitle': 'Проверка реальности',
      'appMisasoc': 'Misasoc',
      'appAtaraxy': 'Ataraxy',
      'changeHabitLayout':
          'Карточки привычек перерисованы: чекбокс наверху, иконка типа под ним',
      'changeHabitFit':
          'Строки привычек теперь хорошо вмещают длинные названия, заметки и метки дней',
      'changePerfectionismTitle':
          'Карточки перфекционизма теперь используют правильный регистр заголовков',
      'changeHabitStreak':
          'Возвращены точки 7-дневной серии на каждой карточке привычки',
      'changeHabitSections':
          'Привычки теперь делятся на Полезные / Вредные, если есть оба типа',
      'changeAlarmSounds':
          'Удалённые звуки будильника остаются удалёнными при создании новых',
      'changeTimerSounds':
          'Удалённые звуки таймера остаются удалёнными при создании новых',
      'changeRcRandom':
          'Уведомления проверок реальности теперь срабатывают в случайное время со случайным текстом',
      'changeGrokTheme': 'Тема Grok переведена на монохром светлую/тёмную',
      'changeMealCards':
          'Карточки питания теперь с ежедневным набором случайных цветов и иконок',
      'changeDropdowns': 'Выпадающие списки закруглены в настройках и задачах',
      'changeSnackbar': 'Улучшена анимация снекбаров',
      'changeSwipeSnap':
          'Свайп между разделами теперь плавно прилипает к точке',
      'changeCornerSwipe': 'Верхние края закругляются при свайпе',
      'changeRoundedTiles': 'Плитки настроек теперь закруглены',
      'changeCategoryLimit': 'Лимит названия категории уменьшен до 15 символов',
      'changeAuthorLinks':
          'Добавлены ссылки на приложения автора: Ataraxy и MSoc',
      'changePrev1': 'Улучшения привычек, задач и будильников',
      'changePrev2': 'Добавлен PIN-замок',
      'changePrev3': 'Экспорт/импорт данных',
      'changePrev4': 'Модуль питания с 7-дневной историей',
      'motivationQuote1': 'Лёгкая жизнь начинается с простого «достаточно».',
      'motivationQuote2': 'Не всё нужно успеть — многое можно просто отпустить.',
      'motivationQuote3': 'Дыши глубже: спешка не ускоряет, а только утомляет.',
      'motivationQuote4': 'Маленький шаг без напряжения длится дольше рывка.',
      'motivationQuote5': 'Позволь себе отдыхать, не заслужив этого.',
      'motivationQuote6': 'Простое утро делает лёгким весь день.',
      'motivationQuote7': 'Тебе не нужно быть лучшим — достаточно быть настоящим.',
      'motivationQuote8': 'Отпусти то, что не в твоих руках, и станет легче дышать.',
      'motivationQuote9': 'Тишина — не пустота, а место для себя.',
      'motivationQuote10': 'Делай меньше, но спокойнее.',
      'motivationQuote11': 'Лёгкость — это не лень, а верный ритм.',
      'motivationQuote12': 'Сегодня достаточно одного доброго дела.',
      'motivationQuote13': 'Не сравнивай свой путь с чужим: у каждого свой темп.',
      'motivationQuote14': 'Разреши себе не знать всех ответов.',
      'motivationQuote15': 'Спокойный ум решает быстрее усталого.',
      'motivationQuote16': 'Убери лишнее — и жизнь станет просторнее.',
      'motivationQuote17': 'Скажи себе «я справляюсь», и станет легче.',
      'motivationQuote18': 'Отдых — часть работы, а не награда за неё.',
      'motivationQuote19': 'Мягкость к себе сильнее строгости.',
      'motivationQuote20': 'Не гони день — проживи его.',
      'motivationQuote21': 'То, что легко, не значит «плохо».',
      'motivationQuote22': 'Начни с малого и не торопи финал.',
      'motivationQuote23': 'Твоя ценность не зависит от скорости.',
      'motivationQuote24': 'Оставь на сегодня одну заботу меньше.',
      'motivationQuote25': 'Живи так, чтобы вечером хотелось выдохнуть с улыбкой.',
      'motivationQuote26': 'Простота — самая недооценённая роскошь.',
      'motivationQuote27': 'Не тащи вчерашнее в новый день.',
      'motivationQuote28': 'Улыбка — самый короткий путь к лёгкости.',
      'motivationQuote29': 'Позволь себе медленный день без вины.',
      'motivationQuote30': 'Хорошо там, где не спешишь.',
      'motivationQuote31': 'Один вдох — уже маленькая пауза.',
      'motivationQuote32': 'Делай то, что возвращает тебе силы.',
      'motivationQuote33': 'Не всякую мысль нужно додумывать.',
      'motivationQuote34': 'Лёгкость рождается из честного «нет».',
      'motivationQuote35': 'Ты имеешь право на спокойный вечер.',
      'motivationQuote36': 'Меньше суеты — больше жизни.',
      'motivationQuote37': 'Ошибка — это просто поворот, а не провал.',
      'motivationQuote38': 'Будь к себе таким же добрым, как к другу.',
      'motivationQuote39': 'Твой ритм — правильный, если тебе в нём хорошо.',
      'motivationQuote40': 'Утро начинается не с дел, а с дыхания.',
      'motivationQuote41': 'Не заполняй каждую минуту — оставь место чуду.',
      'motivationQuote42': 'Лёгкость — это когда не нужно ничего доказывать.',
      'motivationQuote43': 'Позволь дню быть обычным.',
      'motivationQuote44': 'Тихое «всё хорошо» стоит громких побед.',
      'motivationQuote45': 'Отдыхай, пока не захочется, а не пока не свалишься.',
      'motivationQuote46': 'Чистый стол — чистая голова.',
      'motivationQuote47': 'Отпусти контроль там, где он только утомляет.',
      'motivationQuote48': 'Смотри на небо хотя бы раз в день.',
      'motivationQuote49': 'Меньше экрана — больше воздуха.',
      'motivationQuote50': 'Прогулка без цели лечит лучше планов.',
      'motivationQuote51': 'Скажи спасибо телу за то, что оно несёт тебя.',
      'motivationQuote52': 'Ты не обязан быть продуктивным каждую минуту.',
      'motivationQuote53': 'Скука иногда — это отдых для души.',
      'motivationQuote54': 'Пей воду, дыши, живи сейчас.',
      'motivationQuote55': 'Не откладывай радость на «когда-нибудь».',
      'motivationQuote56': 'Сделай сегодня что-то просто для удовольствия.',
      'motivationQuote57': 'Тихий вечер лучше шумной гонки.',
      'motivationQuote58': 'Позволь себе мечтать без плана.',
      'motivationQuote59': 'Тепло рядом начинается с тепла внутри.',
      'motivationQuote60': 'Одно дело за раз — и мир не рухнет.',
      'motivationQuote61': 'Устал — отдохни, а не сдавайся.',
      'motivationQuote62': 'Не требуй от себя больше, чем от других.',
      'motivationQuote63': 'Радость живёт в мелочах, если их замечать.',
      'motivationQuote64': 'Медленнее — значит внимательнее.',
      'motivationQuote65': 'Прости себя за вчерашнюю усталость.',
      'motivationQuote66': 'Лёгкая жизнь — это выбор, а не удача.',
      'motivationQuote67': 'Начни день с благодарности, а не с тревоги.',
      'motivationQuote68': 'Дом там, где тебе спокойно.',
      'motivationQuote69': 'Не гонись за всем — выбери своё.',
      'motivationQuote70': 'Молчание за чашкой чая — тоже разговор.',
      'motivationQuote71': 'Отпусти чужие ожидания — они не твои.',
      'motivationQuote72': 'Хороший сон — половина лёгкой жизни.',
      'motivationQuote73': 'Живи так, чтобы не хотелось убежать от себя.',
      'motivationQuote74': 'Оставь в дне место для ничего.',
      'motivationQuote75': 'Простое «нет» освобождает целый вечер.',
      'motivationQuote76': 'Не сравнивай своё начало с чьей-то серединой.',
      'motivationQuote77': 'Лёгкость — это доверие к себе.',
      'motivationQuote78': 'Сделай шаг, а не прыжок.',
      'motivationQuote79': 'Улыбнись без причины — причина найдётся.',
      'motivationQuote80': 'Ты не должен всё успеть сегодня.',
      'motivationQuote81': 'День становится добрее, когда его не торопишь.',
      'motivationQuote82': 'Нежность к себе — не слабость.',
      'motivationQuote83': 'Меньше шума, больше смысла.',
      'motivationQuote84': 'Живи сейчас — прошлое уже отдохнуло.',
      'motivationQuote85': 'Позволь хорошему приходить без усилий.',
      'motivationQuote86': 'Отдых — это тоже движение вперёд.',
      'motivationQuote87': 'Твоё спокойствие важнее чужого мнения.',
      'motivationQuote88': 'Каждый вдох — новый шанс начать мягко.',
      'motivationQuote89': 'Лёгкая жизнь начинается с лёгкого взгляда.',
      'motivationQuote90': 'Ты уже достаточно. Просто будь.',
      'areYouSure': 'Уверены?',
      'streakResetDone': 'Стрик сброшен',
      'openSettings': 'Открыть настройки',
      'italic': 'Курсив',
      'berserkCardTitle': 'МАКСИМАЛЬНЫЙ АПГРЕЙД УРОВНЯ BERSERK',
      'berserkCardSubtitle':
          'Зажми «плюс» на любом экране — откроется режим личной силы и фокуса.',
      'taskNotesTitle': 'Вспомнил, что использую…',
      'taskNotesSubtitle':
          'Зажми задачу на 5 секунд — откроется быстрый список с заметкой до 150 символов, которая останется прямо на задаче.',
      'taskNoteSheetTitle': 'Вспомнил, что использую…',
      'taskNoteSheetSubtitle':
          'Запиши короткую заметку до 150 символов — она сохранится на задаче.',
      'taskNoteHint': 'Зачем я держу эту задачу? Для чего она?',
      'clearNote': 'Очистить',
      'taskNoteCleared': 'Заметка очищена',
      'taskNoteSaved': 'Заметка сохранена',
      'berserkTitle': 'МАКСИМАЛЬНЫЙ АПГРЕЙД\nУРОВНЯ BERSERK',
      'berserkSubtitle':
          'Короткий режим силы: внимание, выдержка, действие. Держи «плюс» на любом экране — и он открыт.',
      'berserkPracticeTitle': 'Практика от AGI — шаги на сегодня',
      'berserkMotto': 'Сделай это тихо. Сделай это сегодня.',
      'berserkPrinciple1':
          '💰 Богатеть не от мотивационных обещаний, а от навыка, который ты продаёшь, и дел, которые доводишь до конца.',
      'berserkPrinciple2':
          '🗿 Держать осанку, ясный взгляд и острые скулы через сон, движение, воду и уход за собой.',
      'berserkPrinciple3':
          '🛡️ Замечать манипуляции: пауза, уточняющий вопрос, спокойное «нет» — без оправданий и чувства вины.',
      'berserkPrinciple4':
          '🔥 Каждый день закрывать один дорогой для тебя шаг, даже если он маленький и неидеальный.',
      'berserkPrinciple5':
          '⚔️ Выбирать границы и уважение к себе вместо импульсивной реакции или желания всем понравиться.',
      'berserkPrinciple6':
          '🧠 Тренировать внимание: один блок без телефона, одна задача, один измеримый результат.',
      'berserkPrinciple7':
          '📈 Превращать ошибки в данные: записал, понял причину, изменил действие, повторил.',
      'berserkPrinciple8':
          '👑 Говорить точнее: что тебе нужно, к какому сроку и какой следующий шаг.',
      // Новый год 2027 — каждый день дарят одну шапку, они накапливаются
      'nyEventTitle': 'Каждый день дарят шапку',
      'nyEventBody': 'День {0} из 12 · Шапок собрано: {1}',
      'nyEventFinalDay': 'С Новым годом! Все 12 шапок собраны!',
      'nyMarkBtn': 'Забрать',
      'nyMarkedBtn': 'Получено',
      'nyGiftHint': 'На 12 день — подарок: Полярный набор',
      'nyPrizeDone':
          'Подарок открыт: тема «Метель», скин скважины, 60 дней истории '
          'питания и 30 категорий',
      'nyPrizeGiven': 'Подарок открыт: Полярный набор',
      'nyPrizeTheme': 'Открылась новая тема: «Метель»',
      'nyPrizeReverted': 'Подарок снят: тема «Метель» выключена',
      'nySaveFailed': 'Не удалось сохранить',
      'nyResetTitle': 'Сбросить ивент?',
      'nyResetBody': 'Все собранные шапки и подарок исчезнут навсегда.',
      'nyResetConfirm': 'Сбросить',
    },

    'fr': {
      'alarms': 'Alarmes',
      'habits': 'Habitudes',
      'tasks': 'Tâches',
      'rc': 'CR',
      'realityChecks': 'Vérifications de réalité',
      'rcSettingsTitle': 'Vérifications de réalité',
      'rcSettingsBody':
          'Ajoute ou retire entièrement la section : l’onglet « CR » dans Accueil, le planning et les notifications.',
      'rcSettingsOn': 'Section « Vérifications de réalité » activée',
      'rcSettingsOff': 'Section « Vérifications de réalité » masquée',
      'settings': 'Paramètres',
      'statistics': 'Statistiques',
      'nutrition': 'Nutrition',
      'calories': 'Calories',
      'meals': 'Repas',
      'timers': 'Minuteurs',
      'categories': 'Catégories',
      'category': 'Catégorie',
      'all': 'Tous',
      'uncategorized': 'Sans catégorie',
      'newCategory': 'Nouvelle catégorie',
      'categoryName': 'Nom de la catégorie',
      'manageCategories': 'Gérer les catégories',
      'categoryExists': 'Cette catégorie existe déjà',
      'createCategory': 'Créer',
      'deleteCategory': 'Supprimer la catégorie',
      'deleteMealConfirmTitle': 'Supprimer le repas ?',
      'deleteMealConfirmBody':
          'Ce repas sera supprimé. Cette action est irréversible.',
      'deleteMealConfirm': 'Supprimer le repas',
      'profile': 'Profil',
      'profileAnonymous': 'Anonyme',
      'profileName': 'Nom court',
      'profileNameHint': 'Comment vous appeler ?',
      'profileNameSaved': 'Nom enregistré',
      'profileOnlineTitle': 'Statut en ligne',
      'profileOnlineSwitch': 'Afficher le point rouge',
      'profileOnlineSwitchDesc': 'Les autres verront que vous êtes là',
      'profileMusic': 'Votre musique',
      'profileMusicTrack': 'Ma piste',
      'profileMusicEmpty': 'Ajoutez une piste pour la lire dans le profil',
      'profileMusicAdd': 'Choisir un fichier',
      'profileMusicChange': 'Remplacer',
      'profileMusicSet': 'Musique enregistrée',
      'profileMusicFailed': 'Impossible de charger la musique',
      'profileMusicMissing': 'Fichier introuvable',
      'profileMusicPlaying': 'Lecture d’un son entraînant',
      'profileMusicPaused': 'En pause',
      'profileLeaderboard': 'Classement',
      'profileAddFriend': 'Ajouter un ami',
      'profileNoFriends': 'Ajoutez des amis pour comparer les progrès',
      'profileFriendsFull': 'Le classement compte déjà 50 amis',
      'profileFriendName': "Nom de l'ami",
      'profileFriendScore': 'Points de classement',
      'profileFriendScoreRandom': 'Points aléatoires',
      'profileFriendScoreHint':
          'Les points viennent de l\'activité : habitudes, tâches, jours '
              'dans le journal. Plus de points — plus haut dans le classement.',
      'profileFriendSetScore': 'Points',
      'profilePickAvatar': 'Avatar',
      'profileAvatarFromGallery': 'La vôtre depuis la galerie',
      'profileAvatarSet': 'Avatar mis à jour',
      'profileAvatarFailed': "Impossible de charger l'avatar",
      'profileMe': 'Moi',
      'profileEvents': 'Événements',
      'eventNewYear': 'Événement du Nouvel An',
      'eventNewYearDesc': "Un nouveau chapeau chaque jour jusqu'au 1er janvier",
      'eventNewYearSoon': "L'événement n'a pas encore commencé",
      'eventCeramics': 'Foire de céramique',
      'eventCeramicsDesc': 'Ateliers et cuisson pour débutants',
      'eventCommunity': 'Rencontre de la communauté',
      'eventCommunityDesc': 'Rassemblement en ligne des utilisateurs, chaque mois',
      'about': 'À propos',
      'dataStorageError':
          'Impossible de lire ou d’enregistrer les données locales. Les fichiers existants n’ont pas été modifiés.',
      'updateHashMissing':
          'La version ne fournit pas de SHA-256 valide. Installation annulée.',
      'updateInstalled': 'Mis à jour vers v{v}',
      'updateAvailable': 'Mise à jour disponible',
      'updateAvailableBody': 'Installer la v{v} ?',
      'install': 'Installer',
      'updateInstallBlocked':
          'Le système a bloqué la mise à jour. Autorisez l’installation depuis cette source et réessayez.',
      'updateInstallCancelled': 'Mise à jour annulée',
      'open': 'Ouvrir',
      'patchNotes': 'Notes de mise à jour',
      'soon': 'Bientôt',
      'noAlarms': 'Aucune alarme pour l’instant',
      'noHabits': 'Aucune habitude pour l’instant',
      'noTasks': 'Aucune tâche pour l’instant',
      'noRealityChecks': 'Aucune vérification de réalité pour l’instant',
      'emptyAlarmHint':
          'Créez un rythme doux pour votre journée en une minute.',
      'emptyAlarmAdvice':
          'Commencez par une heure de réveil fiable. Le son et la routine peuvent attendre.',
      'emptyHabitHint':
          'Donnez une place à une petite action que vous pouvez répéter.',
      'emptyHabitAdvice':
          'Une habitude grandit quand elle reste assez simple pour les jours ordinaires.',
      'emptyTaskHint':
          'Gardez la prochaine étape importante visible et facile à terminer.',
      'emptyTaskAdvice':
          'Écrivez une action claire à la fois. Les petites victoires créent l’élan.',
      'emptyRealityHint': 'Transformez un moment ordinaire en pause attentive.',
      'emptyRealityAdvice':
          'Choisissez une question que vous aurez vraiment envie de vous poser.',
      'noTimers': 'Aucun minuteur pour l’instant',
      'noMeals': 'Aucun repas enregistré',
      'theme': 'Thème',
      'language': 'Langue',
      'light': 'Clair',
      'dark': 'Sombre',
      'system': 'Système',
      'themeSystemLight': 'Clair système',
      'peach': 'Pêche',
      'grok': 'Grok',
      'rose': 'Rose',
      'metel': 'Metel', // Nom du thème-cadeau, non traduit
      'followSystem': 'Langue du téléphone',
      'english': 'Anglais',
      'russian': 'Russe',
      'french': 'Français',
      'data': 'Données',
      'export': 'Exporter',
      'import': 'Importer',
      'exportDone': 'Paramètres exportés',
      'importDone': 'Paramètres importés',
      'importError': 'Échec de l’importation',
      'importWrongFile': 'Veuillez sélectionner un fichier .json',
      'license': 'Licence : MIT',
      'madeWithLove': 'Fait avec',
      'refresh': 'Actualiser',
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'delete': 'Supprimer',
      'undo': 'Annuler',
      'soundDeleted': 'Son supprimé',
      'ok': 'OK',
      'back': 'Retour',
      'clear': 'Effacer',
      'done': 'Terminé',
      'add': 'Ajouter',
      'newAlarm': 'Nouvelle alarme',
      'editAlarm': 'Modifier l’alarme',
      'tapToChange': 'Tapez pour changer',
      'repeat': 'Répétition',
      'wakeUpTask': 'Tâche de réveil',
      'taskNone': 'Aucune',
      'taskMath': 'Résoudre un calcul',
      'taskPattern': 'Mémoriser la séquence',
      'taskMemory': 'Jeu de mémoire',
      'label': 'Étiquette',
      'vibrate': 'Vibrer',
      'sound': 'Son',
      'customSound': 'Personnalisé',
      'pin': 'Épingler l’alarme',
      'pinMsg': 'Épinglé',
      'unpinMsg': 'Désépinglé',
      'pinMeal': 'Épingler',
      'unpinMeal': 'Désépingler',
      'renameSound': 'Renommer le son',
      'soundName': 'Nom du son',
      'soundRenamed': 'Son renommé',
      'soundRenameFailed': 'Impossible de renommer le son',
      'labelOnce': 'Une seule fois',
      'labelEveryDay': 'Tous les jours',
      'labelWeekdays': 'Jours ouvrés',
      'labelWeekends': 'Week-end',
      'dayMon': 'Lun',
      'dayTue': 'Mar',
      'dayWed': 'Mer',
      'dayThu': 'Jeu',
      'dayFri': 'Ven',
      'daySat': 'Sam',
      'daySun': 'Dim',
      'alarmNoExact':
          'Autorisation d’alarme exacte refusée. Allez dans Paramètres → Applications → Agysha → Batterie → Aucune restriction',
      'pinLock': 'Code PIN',
      'pinDescription': 'Définir un PIN pour verrouiller l’application',
      'setPin': 'Définir le PIN',
      'changePin': 'Changer le PIN',
      'removePin': 'Supprimer le PIN',
      'enterPin': 'Saisir le PIN',
      'confirmPin': 'Confirmer le PIN',
      'wrongPin': 'PIN incorrect',
      'pinsDoNotMatch': 'Les PIN ne correspondent pas',
      'exit': 'Quitter',
      'exitConfirmTitle': 'Veux-tu vraiment prendre la pilule verte ?',
      'exitConfirmBody': 'Le bouton « Quitter » fermera l’application.',
      'newHabit': 'Nouvelle habitude',
      'editHabit': 'Modifier l’habitude',
      'habitName': 'Nom de l’habitude',
      'streak': 'jours d’affilée',
      'habitType': 'Type',
      'habitTypeGood': 'Utile',
      'habitTypeBad': 'Nuisible',
      'habitDays': 'Jours de la semaine',
      'remindAll': 'Rappelle-toi tout',
      'remindAt': 'Rappeler à',
      'remindOffHint': 'Rappellera l’habitude à l’heure choisie',
      'remindOnHint': 'Chaque jour ou les jours sélectionnés',
      'remindCustomText': 'Texte du rappel (max 60 car.)',
      'remindCustomHint': 'Ex: Il est temps de boire de l’eau',
      'habitDaysHint': 'Vide = tous les jours',
      'everyDay': 'Tous les jours',
      'habitNotesBtn': 'Statut',
      'habitStatusTitle': 'À retenir',
      'habitStatusHint': 'Petit rappel',
      'habitNotesTitle': 'Ce qu’il faut retenir',
      'habitNotesHint': 'Notez ce qui compte',
      'habitPinOnlyGood': 'Seules les habitudes utiles peuvent être épinglées',
      'habitPinned': 'Habitude épinglée',
      'habitUnpinned': 'Habitude désépinglée',
      'habitsSectionGood': 'Utiles',
      'habitsSectionBad': 'Nuisibles',
      'tasksSectionDone': 'Archivées',
      'newTask': 'Nouvelle tâche',
      'editTask': 'Modifier la tâche',
      'taskTitle': 'Titre de la tâche',
      'completed': 'Terminée',
      'description': 'Description',
      'notes': 'Notes',
      'priority': 'Priorité',
      'priorityLow': 'Basse',
      'priorityMedium': 'Moyenne',
      'priorityHigh': 'Haute',
      'dueDate': 'Échéance',
      'dueNone': 'Sans échéance',
      'dueToday': "Aujourd'hui",
      'dueTomorrow': 'Demain',
      'dueIn3Days': 'Dans 3 jours',
      'dueInWeek': 'Dans une semaine',
      'duePickDate': 'Choisir une date',
      'estimate': 'Durée',
      'estimateNone': 'Sans limite',
      'overdue': 'En retard',
      'dragToReorder': 'Glisser pour réorganiser',
      'overallCompletion': 'Progression globale',
      'doneToday': 'Fait aujourd’hui',
      'refreshed': 'Actualisé',
      'newRc': 'Nouvelle vérification',
      'editRc': 'Modifier la vérification',
      'rcQuestion': 'Que vous demander ?',
      'rcDone': 'Vérification de réalité faite !',
      'rcToday': 'aujourd’hui',
      'rcChecks': 'vérifications au total',
      'rcStat': 'Vérifications de réalité',
      'monthChartTitle': '30 derniers jours',
      'monthChartHabits': 'Habitudes',
      'monthChartTasks': 'Tâches',
      'monthChartBest': 'meilleur jour',
      'monthChartHint': 'Chaque barre représente un jour. Sa hauteur indique le travail accompli : habitudes en bas, tâches en haut. La colonne d’aujourd’hui est mise en évidence ; l’étoile marque le meilleur jour.',
      'monthChartDays': 'jours faits',
      'rcReset': 'Réinitialiser les stats',
      'rcResetBody':
          'Réinitialiser tous les compteurs de vérifications à zéro ?',
      'rcExit': 'Quitter',
      'disableRcTitle': 'Désactiver les vérifications de réalité ?',
      'disableRcBody':
          "La section va s'estomper et la bascule réapparaîtra. Les vérifications ne seront plus comptées dans les statistiques.",
      'disableRcLongHint': 'Appui long sur le titre pour désactiver',
      'disable': 'Désactiver',
      'rcChecksPerDay': 'Vérifications par jour',
      'rcTimeRange': 'Plage horaire',
      'rcFrom': 'De',
      'rcTo': 'À',
      'rcScheduled': 'programmées',
      'rcText1': 'Est-ce un rêve ?',
      'rcText2': 'Regardez vos mains. Pouvez-vous compter les doigts ?',
      'rcText3': 'Essayez de traverser votre paume avec un doigt.',
      'rcText4': 'Lisez cette phrase deux fois. Le texte a-t-il changé ?',
      'rcText5':
          'Regardez autour de vous — connaissez-vous vraiment cet endroit ?',
      'rcText6': 'Que faisiez-vous il y a dix minutes ? Était-ce réel ?',
      'rcText7':
          'Touchez le mur le plus proche. La texture est-elle correcte ?',
      'rcText8': 'Dites votre nom à voix haute. A-t-il sonné comme vous ?',
      'perfectionism': 'Lutte contre le perfectionnisme',
      'perfectionismHint': 'Sélection quotidienne contre le perfectionnisme',
      'perfTitle1': 'TOC',
      'perfTitle2': 'Imperfection',
      'perfTitle3': 'Stupeur',
      'perfTitle4': 'Tout ou rien',
      'perfTitle5': 'Procrastination',
      'perfTitle6': 'Auto-critique',
      'perfTitle7': 'Rituels mentaux',
      'perfTitle8': 'Intolérance',
      'perfTitle9': 'Hyper-contrôle',
      'perfTitle10': 'Le calme n’est pas de la paresse',
      'perfTitle11': 'Boucle de honte',
      'perfTitle12': 'Hypervigilance',
      'perfTitle13': 'Ancrage',
      'perfTitle14': 'Signal du corps',
      'perfTitle15': 'Piège à idées',
      'perfTitle16': 'Développement personnel comme rituel',
      'perfTitle17': 'Équilibre',
      'perfTitle18': 'Exploration',
      'perfTitle19': 'Grandir dans le désordre',
      'perfTitle20': 'Les objets racontent des histoires',
      'perf1Short': 'Autorisez le désordre.',
      'perf2Short': 'Un micro-pas bat la stupeur.',
      'perf3Short': 'Petit aujourd’hui > grand plan.',
      'perf4Short': 'Terminé suffit. Le parfait est l’ennemi.',
      'perf5Short': 'Procrastination = peur, pas paresse.',
      'perf6Short': 'Les mots ne sont pas une sentence.',
      'perf7Short': 'Nommez la boucle et cassez-la.',
      'perf8Short': 'L’incertitude n’est pas un danger.',
      'perf9Short': 'Lâchez prise pour mieux contrôler.',
      'perf10Short': 'Pause ≠ défaut.',
      'perf11Short': 'La honte ne vous construit pas.',
      'perf12Short': 'Ne cherchez pas les problèmes — vivez.',
      'perf13Short': 'Sentez vos pieds, vous êtes là.',
      'perf14Short': 'Votre corps dit la vérité.',
      'perf15Short': 'Penser n’est pas faire.',
      'perf16Short': 'Tout progrès n’est pas une amélioration.',
      'perf17Short': 'Stabilité avant intensité.',
      'perf18Short': 'La curiosité est une sortie.',
      'perf19Short': 'La saleté fait partie de l’art.',
      'perf20Short': 'Tout autour de vous a été choisi.',
      'perf1Full':
          'Le désordre n’est pas l’ennemi.\nUne étagère de travers reste une étagère.\nTerminé bat parfait.\nLe progrès > la perfection.',
      'perf2Full':
          'L’imperfection est aussi très bien.\nLe négatif fait partie du travail, pas d’un verdict.\nFermez les yeux, faites un petit pas et continuez.\nVous n’avez pas besoin d’être parfait pour avancer.',
      'perf3Full':
          'La stupeur est un signal, pas un mur.\nFaites un micro-pas : une ligne, un clic.\nLe mouvement tue la peur.\nC’est le moment de faire quelque chose de petit.',
      'perf4Full':
          'Terminé suffit.\nLe parfait est l’ennemi du bien.\nCommencez mal. Vous affinerez plus tard.\nLe mouvement bat la perfection.',
      'perf5Full':
          'Procrastination = peur du résultat, pas paresse.\nCommencez 2 minutes — le corps en voudra plus.\nL’action brûle l’anxiété.\nN’importe quel début bat la peur.',
      'perf6Full':
          'Vous êtes déjà en train de faire. L’auto-destruction n’accélère pas la croissance.\nSoyez à vous-même ce que vous seriez à un ami.\nBaissez le volume du critique intérieur.\nLa douceur donne plus que les cris.',
      'perf7Full':
          'L’esprit boucle sur la même pensée.\nNommez-la : « c’est un TOC » et détournez le regard.\nNe résolvez pas — observez.\nChaque retour est plus faible que le précédent.',
      'perf8Full':
          'Le besoin de tout savoir est un piège.\nVivez la question.\nTolérez le non-savoir.\nLa certitude est un fantasme ; le courage est réel.',
      'perf9Full':
          'Serrer chaque vis vous épuise.\nLâchez la pression.\nFaites moins, mais faites-le vraiment.\nLa liberté vit dans l’espace entre stimulus et réponse.',
      'perf10Full':
          'Se reposer n’est pas abandonner.\nLa pause peut être la chose la plus productive.\nAssoyez-vous avec. Respirez. Revenez quand vous êtes prêt.',
      'perf11Full':
          'Les boucles de honte vous paralysent.\nNommez-la. Elle s’adoucira.\nVous êtes toujours en route.',
      'perf12Full':
          'Arrêtez de scruter le monde à la loupe.\nLes défauts que vous cherchez, personne d’autre ne les voit.\nIl n’y a pas de danger — seulement un focus tendu.\nÉlargissez la fenêtre, le calme revient.',
      'perf13Full':
          'Quand les pensées s’affolent, pressez vos pieds au sol.\nAir frais. Son léger.\nCinq choses que vous voyez maintenant.\nCe moment suffit.',
      'perf14Full':
          'Le corps parle plus honnêtement que l’esprit.\nL’anxiété serre les épaules ; la peur serre le ventre.\nAvant de réfléchir, écoutez.\nIl sait en premier et ne ment pas.',
      'perf15Full':
          'Un plan parfait dans la tête ne vaut rien.\nÉcrivez une mauvaise phrase. Faites un geste laid.\nFaire bat planifier à chaque fois.',
      'perf16Full':
          'Collectionner des conseils, lire des recommandations, ajuster des routines — cela peut aussi être un rituel.\nDemandez : ai-je vraiment fait quelque chose aujourd’hui ?',
      'perf17Full':
          'Les petites actions quotidiennes battent les sursauts héroïques.\nUne minute de respiration > une heure de surmenage.\nChoisissez le chemin qui dure.',
      'perf18Full':
          'La curiosité est l’antidote au perfectionnisme.\nDemandez : que se passe-t-il si je tente autrement ?\nUne erreur est une reconnaissance, pas un échec.\nLe chemin est plus intéressant que le résultat.',
      'perf19Full':
          'L’imperfection laisse des traces qui prouvent que vous étiez là.\nLes surfaces parfaites cachent la main.\nVotre désordre a de la valeur.',
      'perf20Full':
          'Regardez cinq objets dans la pièce.\nChacun a été fait par quelqu’un qui a lutté, s’est adapté, a réessayé.\nVous faites partie de cette chaîne.',
      'wtTest': 'Tester la tâche',
      'wtSolved': 'Bravo ! Vous êtes réveillé !',
      'wtDismiss': 'Arrêter l’alarme',
      'wtWrong': 'Faux ! Réessayez.',
      'wtMathTitle': 'Réussissez ce calcul pour arrêter l’alarme',
      'wtAnswerHint': 'Entrez la réponse',
      'wtCheck': 'Vérifier',
      'wtPatternTitle': 'Mémorisez la séquence, puis tapez-la',
      'wtPatternWatch': 'Regardez attentivement',
      'wtMemoryTitle': 'Souvenez-vous des chiffres, puis tapez-les',
      'overthinking': 'Rumination mentale',
      'procrastination': 'Procrastination',
      'selfCriticism': 'Auto-critique',
      'notifications': 'Notifications',
      'notificationsDesc': 'Activer ou désactiver toutes les notifications',
      'batteryOptimization': 'Optimisation de la batterie',
      'batteryOptDesc': 'Désactiver pour des alarmes fiables',
      'batteryOpened': 'Paramètres de batterie ouverts',
      'batterySettings': 'Paramètres de batterie',
      'batterySettingsDesc':
          'Désactiver l’optimisation pour des alarmes fiables',
      'fullscreenNotif': 'Notifications plein écran',
      'fullscreenNotifDesc':
          'Afficher l’alarme par-dessus l’écran de verrouillage',
      'fullScreenNotifTitle': 'Notifications plein écran',
      'fullScreenNotifBody':
          'Requis pour que l’alarme s’affiche par-dessus l’écran de verrouillage',
      'fullScreenGrantMissing':
          'Le système a désactivé l’affichage plein écran. L’alarme ouvrira quand même son écran, mais mieux vaut réactiver l’autorisation.',
      'autostart': 'Démarrage auto',
      'autostartDesc': 'Autoriser l’alarme quand l’application est fermée',
      'popupWarningTitle': 'Important !',
      'popupWarningBody':
          'Pour que les alarmes se déclenchent, autorisez les notifications et l’intent plein écran.',
      'popupWarningOpen': 'Ouvrir les paramètres',
      'popupWarningDismiss': 'Plus tard',
      'dontShowAgain': 'Ne plus afficher',
      'settingsCantOpen':
          'Impossible d’ouvrir les paramètres. Ouvrez-les manuellement → Notifications / Batterie.',
      'welcomeTitle': 'Bienvenue dans Agysha !',
      'welcomeBody':
          'Important pour la ponctualité des alarmes : autorisez les notifications et l’activité en arrière-plan sans restriction. Vous pourrez régler ces autorisations maintenant ou plus tard.',
      'welcomeGo': 'Aller aux paramètres',
      'welcomeSkip': 'Passer',
      'maxAlarms': 'Maximum 10 alarmes',
      'maxHabits': 'Maximum 100 habitudes',
      'maxTasks': 'Maximum 150 tâches',
      'maxRc': 'Maximum 1 vérification',
      'maxTimers': 'Maximum 5 minuteurs',
      'maxCat': 'Maximum {n} catégories',
      'maxCal': 'Maximum 10000 kcal',
      'maxCalPerMeal': 'Maximum 10000 kcal par repas',
      'fillAllFields': 'Veuillez remplir tous les champs',
      'mealAdded': 'Repas ajouté avec succès',
      'kcalShort': 'kcal',
      'mlShort': 'ml',
      'water': 'Eau',
      'waterField': 'Eau, ml',
      'calorieNorm': 'Limite quotidienne',
      'ofPrefix': 'sur',
      'normSaved': 'Objectif enregistré',
      'mealsToday': 'Repas aujourd’hui',
      'macroP': 'Protéines',
      'macroF': 'Lipides',
      'macroC': 'Glucides',
      'macroPSingle': 'P',
      'macroFSingle': 'L',
      'macroCSingle': 'G',
      'trends': 'Tendances',
      'trendsWindow': 'Sur {n} jours',
      'avgPerDay': 'Moyenne par jour',
      'daysOnTarget': 'jours dans l’objectif',
      'bestDay': 'meilleur jour',
      'maxWaterPerMeal': 'Maximum 3000 ml par repas',
      'needNameOrWater': 'Indiquez un plat ou de l’eau',
      'maxDigitsHit': 'Pas plus de chiffres',
      'clearAll': 'Effacer',
      'backspace': 'Retour',
      'diagnostics': 'Diagnostics',
      'diagAlarmTest': 'Tester la notification d’alarme',
      'testAlarm': 'Tester l’alarme',
      'diagRcTest': 'Tester la notification CR',
      'diagSoundTest': 'Tester le son par défaut',
      'diagSent': 'Notification envoyée !',
      'diagSoundPlayed': 'Son joué !',
      'diagNotEnabled': 'Les notifications sont désactivées',
      'diagEnableNotif':
          'Notifications désactivées — ouvrez les paramètres pour les activer.',
      'diagError': 'Erreur',
      'resetWarnings': 'Réinitialiser les avertissements',
      'warningsResetDone': 'Avertissements réinitialisés — ils réapparaîtront',
      'mildImprovements': 'Améliorations mineures',
      'experimentalSettings': 'Expérimental',
      'experimentalDesc': 'Afficher/masquer la section minuteurs (conservés)',
      'aiGuide': 'Guide IA',
      'aiGuideSub': 'Coach d’habitudes',
      'adaName': 'Ada',
      'adaTagline': 'rien à faire',
      'aiClear': 'Effacer le chat',
      'aiWindow': 'Réduire en fenêtre',
      'aiWindowOff': 'Désactiver la fenêtre',
      'aiWindowHint':
          'Réduite en mini-fenêtre — faites-la glisser, touchez pour revenir',
      'aiSystemWindowHint':
          'Ada est maintenant en mini-fenêtre au-dessus des autres apps — fermez-la là-bas',
      'aiOverlayPermissionHint':
          'Autorisez Agysha à s’afficher par-dessus les autres apps pour activer la mini-fenêtre',
      'aiOverlayEmpty': 'Discute avec Ada',
      'aiInputHint': 'Message…',
      'pinLimit': 'Vous pouvez épingler jusqu’à 10 messages',
      'aiUndo': 'Annuler',
      'adaTracking': 'Suivi Ada',
      'adaTrackingDesc':
          'Ada écrit le rapport du matin à 08:00 et le bilan du soir à 21:00 directement dans le chat — pas besoin de notifications.',
      'adaTrackingOn':
          'Ada écrit désormais dans le chat chaque jour à 08:00 et 21:00',
      'adaQuota': 'Ada : N gratuites restantes aujourd’hui',
      'aiChipHabit': 'Habitude',
      'aiChipTask': 'Tâche',
      'aiChipAlarm': 'Alarme',
      'aiChipRC': 'Vérif. réalité',
      'aiChipMeal': 'Repas',
      'aiWebSearch': 'Recherche web',
      'aiWebSearchOn': 'Recherche web ACTIVE',
      'adaEmptyChat': 'Ada ouvrira la voie ―\npar ici, ou par là',
      'readReceipt': 'Lu',
      'readReceiptAt': 'Lu à',
      'aiGuideHint': 'Demande-moi',
      'aiComposing': 'J’écris',
      'aiEmptyAnswer': 'Hmm, je n’ai pas pu formuler de réponse. Réessaie !',
      'share': 'Partager',
      'aiGuideToggle': 'Activer le guide IA',
      'aiGuideDesc':
          'Un petit cercle apparaît à côté du bouton « + » et ouvre un mini-chat.',
      'aiGuideKey': 'Clé Poolside (optionnelle)',
      'aiGuideKeyHint': 'Collez votre clé Laguna',
      'aiGuideKeyNote':
          'Fournisseurs gratuits : Kilo, OVHcloud, Murakumo et AI Horde. La clé Poolside est facultative.',
      'aiGuideKeyNoteProviders': 'Kilo, OVHcloud, Murakumo et AI Horde',
      'aiGuideKeyNoteTail': '',
      'geminiKey': 'Clé Gemini (optionnelle — l’Ada la plus vive et la plus chaude)',
      'geminiKeyHint': 'Colle ta clé Google AI Studio',
      'freeFallbacks': 'Solutions de secours gratuites :',
      'aiResort': 'L’IA est en vacances, attends un peu',
      'retry': 'Réessayer',
      'changeIcon': 'Changer l’icône',
      'chooseIcon': 'Choisir une icône',
      'timeMode': 'Mode horaire',
      'addTime': 'Ajouter une heure',
      'today': 'Aujourd’hui',
      'yesterday': 'Hier',
      'todayErased': 'Aujourd’hui effacé',
      'changelogTitle': 'Nouveautés',
      'dailyMotivation': 'Motivation du jour',
      'addMeal': 'Ajouter un repas',
      'tipSugarTitle': 'Bouclier anti-sucre',
      'tipSugarBody':
          'Si le sucré est emballé, il veut rester au magasin. Choisissez un fruit, du chocolat noir ou de l’eau.',
      'tipSugarBody2':
          'Les protéines rassasient plus longtemps. Ajoutez un œuf, un yaourt ou des noix à chaque repas — le grignotage cessera de vous hanter.',
      'tipWaterTitle': 'L’eau d’abord',
      'tipWaterBody':
          'Souvent la soif porte un masque de faim. Buvez un verre d’eau et attendez 10 minutes avant de vous resservir.',
      'tipProteinTitle': 'Ancrage protéiné',
      'tipProteinBody':
          'Les protéines rassasient plus longtemps. Ajoutez un œuf, un yaourt ou des noix à chaque repas — le grignotage cessera de vous hanter.',
      'tipWalkTitle': 'Faites une marche',
      'tipWalkBody':
          '10 minutes de marche tuent une envie plus vite que la volonté.',
      'tipCoffeeTitle': 'Café noir',
      'tipCoffeeBody':
          'Un café noir peut calmer l’envie de sucré pendant 30 à 40 minutes.',
      'tipColdWaterTitle': 'Eau glacée',
      'tipColdWaterBody':
          'Un verre d’eau glacée réinitialise instantanément le corps et l’esprit — le choc thermique casse la boucle du craving.',
      'tipMindfulTitle': 'Mangez en pleine conscience',
      'tipMindfulBody':
          'Posez le téléphone et mâchez lentement. En 20 minutes, le cerveau rattrape enfin l’estomac.',
      'tipSleepTitle': 'Le sommeil contrôle l’appétit',
      'tipSleepBody':
          'Moins de 7 heures de sommeil fait grimper les hormones de faim. Protégez votre sommeil et les fringales nocturnes faibliront.',
      'tipVeggiesTitle': 'Légumes d’abord',
      'tipVeggiesBody':
          'Commencez chaque repas par des légumes ou une salade. Les fibres rassasient avant même que la nourriture plus lourde n’arrive.',
      'tipChewTitle': 'Comptez les mastications',
      'tipChewBody':
          'Essayez 20 mastications par bouchée. Cela ralentit, améliore la digestion et réduit naturellement la portion.',
      'tipFiberTitle': 'Fibres contre la faim',
      'tipFiberBody':
          'Les céréales complètes et les légumes rassasient plus longtemps que les glucides raffinés.',
      'tipNoSnackTitle': 'Évitez le rayon snacks',
      'tipNoSnackBody':
          'Si vous n’avez pas faim au point de manger une pomme, vous vous ennuyez ou avez soif.',
      'tipSpicesTitle': 'Relevez les saveurs',
      'tipSpicesBody':
          'Les saveurs fortes signalent plus vite la satiété. Ajoutez herbes, piment ou citron pour ralentir la prise alimentaire.',
      'tipBreakfastTitle': 'Petit-déjeuner ancrage',
      'tipBreakfastBody':
          'Un démarrage riche en protéines évite le coup de barre de la matinée et le grignotage aléatoire.',
      'tipPortionTitle': 'Petite assiette, même repas',
      'tipPortionBody':
          'Les repères visuels trompent le cerveau. Une assiette plus petite vous rassasiera avec moins.',
      'tipAlcoholTitle': 'L’alcool lève les freins',
      'tipAlcoholBody':
          'Même un seul verre réduit le self-contrôle et augmente les fringales nocturnes.',
      'tipMindfulHungerTitle': 'Nommez votre faim',
      'tipMindfulHungerBody':
          'Demandez : est-ce une vraie faim, une envie ou une alimentation émotionnelle ? La nommer réduit l’impulsion.',
      'tipConsistencyTitle': 'Même rythme',
      'tipConsistencyBody':
          'Manger aux mêmes heures stabilise la glycémie. Les repas aléatoires perturbent le métabolisme.',
      'tipFruitCravingTitle': 'Fruit plutôt que sucre',
      'tipFruitCravingBody':
          'Une pomme ou des baies satisfont la dent sucrée sans le pic de glycémie.',
      'tipDarkChocolateTitle': 'Chocolat noir',
      'tipDarkChocolateBody':
          'Deux carrés de chocolat noir à 85% satisfont la tentation sans culpabilité.',
      'tipYogurtTitle': 'Yaourt aux fruits rouges',
      'tipYogurtBody':
          'Un yaourt nature avec des baies est un dessert sans fausse honte qui fait office de récompense.',
      'tipWarmDrinkTitle': 'Boisson chaude',
      'tipWarmDrinkBody':
          'Une boisson chaude sans sucre apaise les envies de sucré.',
      'tipReplaceTitle': 'Remplacer, pas interdire',
      'tipReplaceBody':
          'Le cerveau résiste aux interdits ; il réagit mieux aux remplacements.',
      'tipStressSugarTitle': 'Stress ≠ sucre',
      'tipStressSugarBody':
          'Le stress amplifie l’envie de sucré. Allez marcher plutôt que grignoter.',
      'tipWaitTitle': 'Règle des 10 minutes',
      'tipWaitBody':
          'Attendez 10 minutes avant de céder à une envie — la plupart se dissipent d’elles-mêmes.',
      'tipOvereatTitle': 'Ne mangez pas jusqu’à éclater',
      'tipOvereatBody':
          'Arrêtez-vous quand vous êtes à l’aise, pas quand vous êtes plein. Le cerveau a 20 minutes pour comprendre la satiété.',
      'tipSugarSwapTitle': 'Remplacez le sucre',
      'tipSugarSwapBody':
          'Une envie de sucré ? Prenez un fruit, un carré de chocolat noir ou un thé à la cannelle — le goût est là, le pic de sucre non.',
      'tipSaltBloatTitle': 'Moins de sel, moins de gonflement',
      'tipSaltBloatBody':
          'Snacks salés et sauces retiennent l’eau. Assaisonnez avec des herbes, du citron et des épices — le gonflement part en quelques jours.',
      'tipPotassiumTitle': 'Le potassium contre la rétention',
      'tipPotassiumBody':
          'Bananes, verdure, avocat et légumineuses aident à évacuer l’eau en excès. Ajoutez-en à chaque repas.',
      'tipWaterBloatTitle': 'L’eau chasse l’eau',
      'tipWaterBloatBody':
          'Quand vous buvez trop peu, le corps stocke le liquide. 6 à 8 verres par jour : l’habitude anti-gonflement la plus simple.',
      'tipLateSaltTitle': 'Pas de sel le soir',
      'tipLateSaltBody':
          'Un dîner salé se voit sur le visage au matin. Gardez le repas du soir léger et peu salé.',
      'tipMoveBloatTitle': 'Bougez pour drainer',
      'tipMoveBloatBody':
          '20 minutes de marche ou un effort léger relancent la lymphe — et le gonflement baisse nettement.',
      'tipProcessedTitle': 'Évitez le transformé',
      'tipProcessedBody':
          'Charcuterie, chips et plats préparés sont des bombes de sel. Cuisinez des aliments bruts — et les gonflements s’apaisent.',
      'tipHerbalTitle': 'Tisanes',
      'tipHerbalBody':
          'Pissenlit, ortie et thé vert soutiennent doucement les reins et aident à éliminer l’eau en excès.',
      'tipSwellingCheckTitle': 'Quand consulter',
      'tipSwellingCheckBody':
          'Si le gonflement dure des semaines, est unilatéral ou douloureux — consultez un médecin plutôt que de le « dissoudre » par le régime.',
      'newTimer': 'Nouveau minuteur',
      'editTimer': 'Modifier le minuteur',
      'timerDuration': 'Durée',
      'timerLabel': 'Étiquette',
      'timerDone': 'Minuteur terminé !',
      'timerRunning': 'En cours',
      'timerPaused': 'En pause',
      'timerFinished': 'Terminé',
      'autoSave': 'Sauvegarde auto',
      'autoSaveDesc': 'Enregistrer les données chaque seconde',
      'autoExport': 'Export auto',
      'autoExportHourly':
          'Enregistrer une sauvegarde dans Téléchargements/Agysha chaque heure',
      'autoExportDone': 'Sauvegarde enregistrée dans Téléchargements/Agysha',
      'autoExportFailed': 'Échec de l\'enregistrement de la sauvegarde',
      'clearCache': 'Vider le cache',
      'clearCacheDesc': 'Libérer l’espace des fichiers temporaires',
      'clearCacheDone': 'Cache vidé !',
      'haptics': 'Vibration',
      'hapticsDesc': 'Courte vibration lors des appuis et bascules',
      'sounds': 'Sons',
      'soundsDesc': 'Cliquetis système discret lors des confirmations',
      'reduceMotion': 'Réduire les animations',
      'reduceMotionDesc': 'Désactiver les animations et effets décoratifs',
      'devMode': 'Mode développeur',
      'devModePrompt': 'Saisissez le code d’accès pour continuer',
      'devModeInvalidCode': 'Code incorrect. Veuillez réessayer.',
      'devModeUnlock': 'Déverrouiller',
      'devToolsTitle': 'Outils développeur',
      'devToolsSubtitle': 'Options cachées pour polir finement l’application.',
      'devModeDisable': 'Désactiver le mode développeur',
      'devPromptTitle': 'Que faut-il changer dans l’application ?',
      'devPromptDescription':
          'Notez ici les améliorations souhaitées. Le texte est enregistré automatiquement et inclus dans la sauvegarde.',
      'devPromptHint':
          'Décrivez les changements, le comportement ou le design souhaité…',
      'devPromptSaving': 'Enregistrement…',
      'devPromptSaved': 'Enregistré sur cet appareil',
      'devPromptUnsaved': 'Modifications non enregistrées',
      'devPromptSaveError':
          'Échec de l’enregistrement. Appuyez sur Enregistrer.',
      'devPromptSave': 'Enregistrer',
      'forgeTitle': 'Forge',
      'forgeSubtitle': 'Discussion avec l’agent : pose une question ou demande une modification.',
      'forgeTokenSection': 'ACCÈS GITHUB',
      'forgeTokenHint': 'Fine-grained : Contents, Pull requests — read and write.',
      'startupDiagTitle': 'Agysha s’est arrêtée en sécurité',
      'startupDiagBody':
          'Agysha n’a pas pu terminer son démarrage et s’est arrêtée avant '
          'le premier écran. Rien n’a changé sur le disque. Tu peux réessayer '
          'ou copier/enregistrer les détails ci-dessous.',
      'startupDiagDetailsTitle': 'Détails techniques',
      'startupDiagCopy': 'Copier',
      'startupDiagSave': 'Enregistrer le log',
      'startupDiagSaved': 'Log enregistré :',
      'startupDiagSaveFailed': 'Impossible d’enregistrer le log dans un fichier.',
      'startupDiagCopied': 'Copié dans le presse-papiers.',
      'startupDiagRetry': 'Réessayer',
      'startupDiagRetrying': 'Nouvelle tentative…',
      'startupDiagRetryFailed':
          'Le redémarrage a échoué. L’erreur ci-dessous est inchangée.',
      'forgeTokenCheck': 'Enregistrer',
      'forgeTokenForget': 'Oublier le jeton',
      'forgeTokenOk': 'Jeton valide',
      'forgeTokenInvalid': 'GitHub a rejeté le jeton',
      'forgeTokenReadOnly': 'Pas de droit d’écriture — l’agent ne peut pas committer',
      'forgeTokenEmpty': 'Jeton requis',
      'forgeTokenSaveFailed':
          'Impossible d’enregistrer le jeton — stockage indisponible',
      'forgeTokenForgotten': 'Jeton supprimé',
      'forgeChatSection': 'DISCUSSION',
      'forgeTaskHint': 'Pose une question ou décris la modification…',
      'forgeRun': 'Envoyer',
      'forgeWorking': 'En cours…',
      'forgeTaskEmpty': 'Tâche requise',
      'forgeProvider': 'fournisseur gratuit',
      'forgeLogSection': 'JOURNAL',
      'forgeDone': 'Pull request prête',
      'forgeBranch': 'Branche',
      'forgeFiles': 'fichiers modifiés',
      'forgeSafetyNote':
          'L’agent répond aussitôt aux questions. Les modifications vont dans une branche et une pull request — main reste intact. IA : fournisseurs gratuits intégrés.',
      'forgeThinking': 'L’agent réfléchit…',
      'forgeChatEmpty':
          'Pose une question sur le projet ou décris ce qu’il faut modifier.',
      'forgeClearChat': 'Effacer la discussion',
      'forgeChatCleared': 'Discussion effacée',
      'forgeChanges': 'Modifications',
      'forgeNoChanges': 'Aucune modification cette fois',
      'showPassword': 'Afficher le code',
      'hidePassword': 'Masquer le code',
      'patchDeveloping': 'Comment l\'application évolue',
      'patchRoadmap': 'Petites retouches, PR en 2027',
      'changeSwipeUp': 'Glissez vers le haut sur l\'accueil pour actualiser',
      'changeAdaGuide':
          'Guide IA Ada — un mini-chat qui crée lui-même habitudes, tâches, alarmes, vérifications de réalité et repas',
      'changeSmoothAnim':
          'Animations fluides partout : transitions de sections, paramètres, cartes, interrupteurs',
      'changeStreakFix': 'Séries et coches d’habitudes corrigées',
      'changePinBlur':
          'Le code PIN floute l’application dans les applications récentes',
      'changeNotifIcon': 'Icône de notification — badge K signature',
      'changeAlarmFix':
          'Alarmes : sons restaurés, sélecteur d’heure fonctionne au glissement',
      'changeTaskShelvesContrast':
          'Étagères de tâches : les titres sont lisibles en thème clair et sombre',
      'changeLintCleanup':
          'Rangement interne — l’application est un peu plus fiable',
      'changeTaskShelves':
          'Les tâches sont réparties en étagères « Actives » et « Terminées »',
      'changeTaskMarkFinal':
          'Terminer une tâche est définitif — elle passe à l’étagère des tâches terminées',
      'changeCIUpdate':
          'Les versions sortent plus proprement — refonte de la compilation',
      'changeCategoryDrag':
          'On peut faire glisser les catégories pour les réordonner dans l’éditeur de tâche',
      'changeCategoryReorder':
          'L’ordre des catégories change en douceur et est mémorisé',
      'changeRemindAllCircle':
          '« Tout rappeler » adopte maintenant la teinte des boutons voisins',
      'changePinSmooth':
          'L’écran de verrouillage et l’anneau des habitudes s’animent en douceur',
      'changeFlockEdges':
          'La nuée d’oiseaux apparaît et disparaît en fondu au lieu d’être coupée',
      'changeForgeTokenSave':
          'Forge : l’enregistrement du jeton GitHub fonctionne, le bouton revit',
      'changeForgeAgent':
          'Forge est un vrai agent de discussion : il répond et modifie le code',
      'changeForgePr':
          'Les modifications de l’agent vont sur une branche et ouvrent une pull request',
      'changeForgeFree':
          'Forge fonctionne out of the box avec les fournisseurs gratuits intégrés',
      'changeForgeSection':
          'Le Coin Développeur a reçu la section Forge pour les modifications du dépôt',
      'changeForgeEntry': 'Forge est accessible depuis les Réglages, en trois langues',
      'changeCIMemory':
          'Les builds de release ne plantent plus sur le runner par manque de mémoire Gradle',
      'changeCISigning':
          'Les secrets de signature sont vérifiés d’emblée : une erreur claire au lieu d’un crash',
      'changeAutoUpdateName':
          'La mise à jour compare les versions par nom, donc elle marche avec les APK séparés',
      'changeHamster': 'Hamster : statistiques, recherche et écran PIN plus rapide',
      'changeMutilatedTheme':
          'Nouveau thème MUTILATED — rouge sang clair avec éclaboussures très discrètes',
      'changeElegantEgg':
          'Maintenir la puce MUTILATED 10 secondes révèle l’easter egg « Êtes-vous élégant·e ? »',
      'changeMealConfirm': 'Confirmation avant la suppression d’un repas',
      'changeChatScroll':
          'Le chat Ada reste collé au dernier message pendant le stream et à l’ouverture',
      'changeLangSmooth': 'Le changement de langue est désormais plus fluide',
      'changeEmDash':
          'Tous les tirets visibles sont devenus des tirets longs (em-dash)',
      'changeSplashFix':
          'L’avatar du splash ne clignote plus au démarrage à froid',
      'aboutAuthorTitle': 'À propos de l’auteur',
      'visitellaName': 'Visitella',
      'visitellaDesc': 'Projets, jeux, actualités',
      'aboutAuthorBody': 'Autres applications du même développeur :',
      'supportAuthorTitle': 'Soutenir l’auteur',
      'supportAuthorBody':
          'Agysha est un projet indépendant — sans publicité ni abonnement. Si l’application vous est utile, offrez un café à l’auteur : la plus belle façon de dire merci.',
      'supportAuthorHint': 'Ouvre la page de remerciement dans le navigateur',
      'supportSoonToast':
          'Le paiement via Ozon arrive très bientôt — restez à l’affût !',
      'supportOzonSubtitle': 'Bientôt — soutien par un achat',
      'supportBoostySubtitle': 'Don unique ou abonnement',
      'support': 'Offrir un café',
      'rcNotificationTitle': 'Test de réalité',
      'appMisasoc': 'Misasoc',
      'appAtaraxy': 'Ataraxy',
      'changeHabitLayout':
          'Cartes d’habitudes redesignées : case à cocher en haut, icône de type en dessous',
      'changeHabitFit':
          'Les lignes d’habitudes accueillent mieux les longs titres, notes et libellés de jour',
      'changePerfectionismTitle':
          'Les plaques de perfectionnisme utilisent désormais une casse correcte',
      'changeHabitStreak':
          'Retour des points de série de 7 jours sur chaque carte d’habitude',
      'changeHabitSections':
          'Les habitudes se divisent en Utiles / Nuisibles quand les deux types existent',
      'changeAlarmSounds':
          'Les sons d’alarme supprimés restent supprimés pour les nouvelles alarmes',
      'changeTimerSounds':
          'Les sons de minuteur supprimés restent supprimés pour les nouveaux minuteurs',
      'changeRcRandom':
          'Les notifications de vérification de réalité s’affichent désormais à des heures aléatoires avec un texte aléatoire intégré',
      'changeGrokTheme': 'Thème Grok passé en monochrome clair/sombre',
      'changeMealCards':
          'Les cartes de nutrition utilisent désormais un set quotidien aléatoire de couleurs et d’icônes',
      'changeDropdowns':
          'Listes déroulantes arrondies dans paramètres et tâches',
      'changeSnackbar': 'Animation des snackbars polie',
      'changeSwipeSnap':
          'Le balayage entre sections s’accroche désormais en douceur',
      'changeCornerSwipe': 'Coins supérieurs arrondis pendant le balayage',
      'changeRoundedTiles': 'Tuiles de paramètres désormais arrondies',
      'changeCategoryLimit':
          'Limite du nom de catégorie réduite à 15 caractères',
      'changeAuthorLinks':
          'Liens vers les applications de l’auteur ajoutés : Ataraxy et MSoc',
      'changePrev1': 'Réglages des habitudes, tâches et alarmes',
      'changePrev2': 'Verrou PIN ajouté',
      'changePrev3': 'Export / import des données',
      'changePrev4': 'Module de nutrition avec historique 7 jours',
      'motivationQuote1': 'Une vie légère commence par un simple « assez ».',
      'motivationQuote2': 'Tu n’as pas à tout caser — beaucoup de choses peuvent simplement s’en aller.',
      'motivationQuote3': 'Respire plus profondément : la hâte n’accélère rien, elle fatigue.',
      'motivationQuote4': 'Un petit pas sans effort dure plus longtemps qu’un sprint.',
      'motivationQuote5': 'Permets-toi de te reposer sans l’avoir mérité.',
      'motivationQuote6': 'Un matin simple allège toute la journée.',
      'motivationQuote7': 'Tu n’as pas besoin d’être le meilleur — être vrai suffit.',
      'motivationQuote8': 'Lâche ce qui n’est pas entre tes mains, et respirer devient plus facile.',
      'motivationQuote9': 'Le silence n’est pas un vide — c’est une place pour toi.',
      'motivationQuote10': 'Fais moins, mais plus calmement.',
      'motivationQuote11': 'La légèreté n’est pas de la paresse — c’est le bon rythme.',
      'motivationQuote12': 'Une bonne action suffit pour aujourd’hui.',
      'motivationQuote13': 'Ne compare pas ton chemin à celui d’un autre : chacun a son rythme.',
      'motivationQuote14': 'Permets-toi de ne pas connaître toutes les réponses.',
      'motivationQuote15': 'Un esprit calme résout plus vite qu’un esprit fatigué.',
      'motivationQuote16': 'Enlève le superflu, et la vie s’agrandit.',
      'motivationQuote17': 'Dis-toi « je gère », et cela devient plus léger.',
      'motivationQuote18': 'Le repos fait partie du travail, ce n’est pas une récompense.',
      'motivationQuote19': 'La douceur envers soi est plus forte que la sévérité.',
      'motivationQuote20': 'Ne cours pas après la journée — vis-la.',
      'motivationQuote21': 'Ce qui est facile n’est pas pour autant mauvais.',
      'motivationQuote22': 'Commence petit et ne précipite pas la fin.',
      'motivationQuote23': 'Ta valeur ne dépend pas de ta vitesse.',
      'motivationQuote24': 'Laisse un souci de côté aujourd’hui.',
      'motivationQuote25': 'Vis de sorte qu’au soir tu aies envie de souffler avec un sourire.',
      'motivationQuote26': 'La simplicité est le luxe le plus sous-estimé.',
      'motivationQuote27': 'Ne traîne pas hier dans un nouveau jour.',
      'motivationQuote28': 'Un sourire est le plus court chemin vers la légèreté.',
      'motivationQuote29': 'Permets-toi une journée lente, sans culpabilité.',
      'motivationQuote30': 'On est bien là où l’on ne se presse pas.',
      'motivationQuote31': 'Une respiration, c’est déjà une petite pause.',
      'motivationQuote32': 'Fais ce qui te rend des forces.',
      'motivationQuote33': 'Toute pensée n’a pas besoin d’être terminée.',
      'motivationQuote34': 'La légèreté naît d’un « non » honnête.',
      'motivationQuote35': 'Tu as le droit à une soirée calme.',
      'motivationQuote36': 'Moins d’agitation — plus de vie.',
      'motivationQuote37': 'Une erreur est un virage, pas un échec.',
      'motivationQuote38': 'Sois aussi bienveillant envers toi qu’envers un ami.',
      'motivationQuote39': 'Ton rythme est le bon si tu t’y sens bien.',
      'motivationQuote40': 'Le matin commence non par les tâches, mais par la respiration.',
      'motivationQuote41': 'Ne remplis pas chaque minute — laisse une place à l’émerveillement.',
      'motivationQuote42': 'La légèreté, c’est quand tu n’as rien à prouver.',
      'motivationQuote43': 'Laisse la journée être ordinaire.',
      'motivationQuote44': 'Un « tout va bien » tranquille vaut les grandes victoires.',
      'motivationQuote45': 'Repose-toi avant d’en avoir envie, pas après l’épuisement.',
      'motivationQuote46': 'Un bureau clair, une tête claire.',
      'motivationQuote47': 'Lâche le contrôle là où il ne fait que fatiguer.',
      'motivationQuote48': 'Regarde le ciel au moins une fois par jour.',
      'motivationQuote49': 'Moins d’écran — plus d’air.',
      'motivationQuote50': 'Une promenade sans but guérit mieux que les plans.',
      'motivationQuote51': 'Remercie ton corps de te porter.',
      'motivationQuote52': 'Tu n’es pas obligé d’être productif chaque minute.',
      'motivationQuote53': 'L’ennui est parfois un repos pour l’âme.',
      'motivationQuote54': 'Bois de l’eau, respire, vis maintenant.',
      'motivationQuote55': 'Ne remets pas la joie à « un jour ».',
      'motivationQuote56': 'Fais aujourd’hui quelque chose juste pour le plaisir.',
      'motivationQuote57': 'Une soirée calme vaut mieux qu’une course bruyante.',
      'motivationQuote58': 'Permets-toi de rêver sans plan.',
      'motivationQuote59': 'La chaleur autour commence par la chaleur en dedans.',
      'motivationQuote60': 'Une chose à la fois — et le monde ne s’écroulera pas.',
      'motivationQuote61': 'Fatigué ? Repose-toi, n’abandonne pas.',
      'motivationQuote62': 'N’exige pas plus de toi que des autres.',
      'motivationQuote63': 'La joie vit dans les petites choses, si on les remarque.',
      'motivationQuote64': 'Plus lentement, c’est plus attentif.',
      'motivationQuote65': 'Pardonne-toi ta fatigue d’hier.',
      'motivationQuote66': 'Une vie légère est un choix, pas une chance.',
      'motivationQuote67': 'Commence la journée par la gratitude, pas par l’angoisse.',
      'motivationQuote68': 'On est chez soi là où l’on se sent calme.',
      'motivationQuote69': 'Ne cours pas après tout — choisis ce qui est à toi.',
      'motivationQuote70': 'Le silence devant une tasse de thé est aussi une conversation.',
      'motivationQuote71': 'Lâche les attentes des autres — elles ne sont pas à toi.',
      'motivationQuote72': 'Un bon sommeil, c’est la moitié d’une vie légère.',
      'motivationQuote73': 'Vis de sorte de ne pas vouloir te fuir.',
      'motivationQuote74': 'Laisse dans la journée une place pour rien.',
      'motivationQuote75': 'Un simple « non » libère toute une soirée.',
      'motivationQuote76': 'Ne compare pas ton début au milieu de quelqu’un d’autre.',
      'motivationQuote77': 'La légèreté, c’est la confiance en soi.',
      'motivationQuote78': 'Fais un pas, pas un bond.',
      'motivationQuote79': 'Souris sans raison — la raison viendra.',
      'motivationQuote80': 'Tu n’as pas à tout terminer aujourd’hui.',
      'motivationQuote81': 'La journée devient plus douce quand on ne la presse pas.',
      'motivationQuote82': 'La tendresse envers soi n’est pas une faiblesse.',
      'motivationQuote83': 'Moins de bruit, plus de sens.',
      'motivationQuote84': 'Vis maintenant — le passé s’est déjà reposé.',
      'motivationQuote85': 'Laisse le bon venir sans effort.',
      'motivationQuote86': 'Le repos est aussi un pas en avant.',
      'motivationQuote87': 'Ton calme compte plus que l’avis des autres.',
      'motivationQuote88': 'Chaque souffle est une nouvelle chance de commencer en douceur.',
      'motivationQuote89': 'Une vie légère commence par un regard léger.',
      'motivationQuote90': 'Tu es déjà assez. Sois simplement.',
      'areYouSure': 'Êtes-vous sûr ?',
      'streakResetDone': 'Série réinitialisée',
      'openSettings': 'Ouvrir les paramètres',
      'italic': 'Italique',
      'berserkCardTitle': 'MISE À NIVEAU MAXIMALE DU NIVEAU BERSERK',
      'berserkCardSubtitle':
          'Maintenez le « + » sur n’importe quel écran — un mode de force personnelle et de concentration s’ouvre.',
      'taskNotesTitle': 'Je me suis souvenu pourquoi je l’utilise…',
      'taskNotesSubtitle':
          'Maintenez une tâche pendant 5 secondes — une note rapide de 150 caractères max, conservée directement sur la tâche.',
      'taskNoteSheetTitle': 'Je me suis souvenu pourquoi je l’utilise…',
      'taskNoteSheetSubtitle':
          'Écrivez une courte note de 150 caractères max — elle restera sur la tâche.',
      'taskNoteHint': 'Pourquoi je garde cette tâche ? À quoi sert-elle ?',
      'clearNote': 'Effacer',
      'taskNoteCleared': 'Note effacée',
      'taskNoteSaved': 'Note enregistrée',
      'berserkTitle': 'MISE À NIVEAU MAXIMALE\nDU NIVEAU BERSERK',
      'berserkSubtitle':
          'Un mode de force court : attention, sang-froid, action. Maintenez le « + » n’importe où — et il s’ouvre.',
      'berserkPracticeTitle': 'Pratique d’AGI — les étapes du jour',
      'berserkMotto': 'Fais-le en silence. Fais-le aujourd’hui.',
      'berserkPrinciple1':
          '💵 Enrichissez-vous non pas grâce aux promesses de motivation, mais grâce à la compétence que vous vendez et au travail que vous terminez.',
      'berserkPrinciple2':
          '🗿 Gardez la posture, le regard clair et les pommettes marquées grâce au sommeil, au mouvement, à l’eau et au soin de soi.',
      'berserkPrinciple3':
          '🛡️ Repérez la manipulation : pause, question de clarification, « non » calme — sans excuses ni culpabilité.',
      'berserkPrinciple4':
          '🔥 Chaque jour, franchissez une étape importante, même petite et imparfaite.',
      'berserkPrinciple5':
          '⚔️ Choisissez vos limites et le respect de vous-même plutôt que la réaction impulsive ou le besoin de plaire.',
      'berserkPrinciple6':
          '🧠 Entraînez l’attention : un bloc sans téléphone, une tâche, un résultat mesurable.',
      'berserkPrinciple7':
          '📈 Transformez les erreurs en données : notées, comprises, action changée, répétée.',
      'berserkPrinciple8':
          '👑 Parlez plus précisément : ce dont vous avez besoin, pour quand, et quelle est la prochaine étape.',
      // Nouvel An 2027 — un chapeau offert chaque jour
      'nyEventTitle': 'Un chapeau chaque jour',
      'nyEventBody': 'Jour {0} sur 12 · Chapeaux collectés : {1}',
      'nyEventFinalDay': 'Bonne année ! Les 12 chapeaux sont collectés !',
      'nyMarkBtn': 'Récupérer',
      'nyMarkedBtn': 'Reçu',
      'nyGiftHint': 'Le jour 12 ouvre un cadeau : le set Polaire',
      'nyPrizeDone':
          'Cadeau ouvert : thème Metel, skin de serrure, 60 jours '
          'd historique alimentaire et 30 catégories',
      'nyPrizeGiven': 'Cadeau ouvert : le set Polaire',
      'nyPrizeTheme': 'Nouveau thème disponible : Metel',
      'nyPrizeReverted': 'Cadeau retiré : thème Metel désactivé',
      'nySaveFailed': 'Enregistrement impossible — le chapeau est resté',
      'nyResetTitle': 'Réinitialiser tout l événement ?',
      'nyResetBody': 'Tous les chapeaux collectés et le cadeau disparaîtront.',
      'nyResetConfirm': 'Réinitialiser',
    },
  };

  static String _lookup(String key, BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    // Забытый перевод НЕ должен показываться пользователю как «someKeyName».
    // Сначала пробуем текущую локаль, потом английский как надёжный
    // источник, и лишь в самом конце — сам ключ (такого ключа в словарях
    // просто нет: об этом предупреждает тест паритета локалей).
    return byLocale[key] ?? _data['en']![key] ?? key;
  }

  static String t(String key, BuildContext context, [String? fallback]) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    // Порядок: текущая локаль → явный фолбек → английский → сам ключ.
    // Фолбек раньше стоял раньше английского намеренно (вызывающий код
    // знает, что писать), поэтому его приоритет сохраняем.
    return _emdash(byLocale[key] ?? fallback ?? _data['en']![key] ?? key);
  }

  /// В приложении всё, что выглядит как «-», должно быть длинным тире «—».
  /// Проходим по строке и заменяем дефисы между словами.
  static String _emdash(String s) {
    var out = s;
    // Цифра → дефис → «слово» и «слово — слово» (вокруг — пробелы).
    out = out.replaceAllMapped(
      RegExp(r'(\d)\s*-\s*(\d|\p{L})'),
      (m) => '${m[1]}—${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(\p{L}|,)\s+-\s+(\p{L})', unicode: true),
      (m) => '${m[1]} — ${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(\p{L})\s+-\s(\p{L})', unicode: true),
      (m) => '${m[1]} — ${m[2]}',
    );
    return out;
  }

  static String aboutOf(BuildContext context) => _lookup('about', context);
  static String alarmsOf(BuildContext context) => _lookup('alarms', context);
  static String allOf(BuildContext context) => _lookup('all', context);
  static String backOf(BuildContext context) => _lookup('back', context);
  static String batteryOpenedOf(BuildContext context) =>
      _lookup('batteryOpened', context);
  static String batteryOptDescOf(BuildContext context) =>
      _lookup('batteryOptDesc', context);
  static String batteryOptimizationOf(BuildContext context) =>
      _lookup('batteryOptimization', context);
  static String cancelOf(BuildContext context) => _lookup('cancel', context);
  static String categoryOf(BuildContext context) =>
      _lookup('category', context);
  static String changePinOf(BuildContext context) =>
      _lookup('changePin', context);
  static String darkOf(BuildContext context) => _lookup('dark', context);
  static String deleteOf(BuildContext context) => _lookup('delete', context);
  static String diagnosticsOf(BuildContext context) =>
      _lookup('diagnostics', context);
  static String editAlarmOf(BuildContext context) =>
      _lookup('editAlarm', context);
  static String englishOf(BuildContext context) => _lookup('english', context);
  static String followSystemOf(BuildContext context) =>
      _lookup('followSystem', context);
  static String frenchOf(BuildContext context) => _lookup('french', context);
  static String fullscreenNotifDescOf(BuildContext context) =>
      _lookup('fullscreenNotifDesc', context);
  static String habitsOf(BuildContext context) => _lookup('habits', context);
  static String labelOf(BuildContext context) => _lookup('label', context);
  static String languageOf(BuildContext context) =>
      _lookup('language', context);
  static String lightOf(BuildContext context) => _lookup('light', context);
  static String madeWithLoveOf(BuildContext context) =>
      _lookup('madeWithLove', context);
  static String newAlarmOf(BuildContext context) =>
      _lookup('newAlarm', context);
  static String noAlarmsOf(BuildContext context) =>
      _lookup('noAlarms', context);
  static String noHabitsOf(BuildContext context) =>
      _lookup('noHabits', context);
  static String noRealityChecksOf(BuildContext context) =>
      _lookup('noRealityChecks', context);
  static String noTasksOf(BuildContext context) => _lookup('noTasks', context);
  static String notificationsDescOf(BuildContext context) =>
      _lookup('notificationsDesc', context);
  static String notificationsOf(BuildContext context) =>
      _lookup('notifications', context);
  static String okOf(BuildContext context) => _lookup('ok', context);
  static String peachOf(BuildContext context) => _lookup('peach', context);
  static String roseOf(BuildContext context) => _lookup('rose', context);
  static String pinDescriptionOf(BuildContext context) =>
      _lookup('pinDescription', context);
  static String pinLockOf(BuildContext context) => _lookup('pinLock', context);
  static String rcOf(BuildContext context) => _lookup('rc', context);
  static String realityChecksOf(BuildContext context) =>
      _lookup('realityChecks', context);
  static String refreshOf(BuildContext context) => _lookup('refresh', context);
  static String removePinOf(BuildContext context) =>
      _lookup('removePin', context);
  static String repeatOf(BuildContext context) => _lookup('repeat', context);
  static String russianOf(BuildContext context) => _lookup('russian', context);
  static String saveOf(BuildContext context) => _lookup('save', context);
  static String clearNoteOf(BuildContext context) =>
      _lookup('clearNote', context);
  static String taskNoteClearedOf(BuildContext context) =>
      _lookup('taskNoteCleared', context);
  static String taskNoteSavedOf(BuildContext context) =>
      _lookup('taskNoteSaved', context);
  static String setPinOf(BuildContext context) => _lookup('setPin', context);
  static String settingsOf(BuildContext context) =>
      _lookup('settings', context);
  static String soundOf(BuildContext context) => _lookup('sound', context);
  static String systemOf(BuildContext context) => _lookup('system', context);
  static String tapToChangeOf(BuildContext context) =>
      _lookup('tapToChange', context);
  static String tasksOf(BuildContext context) => _lookup('tasks', context);
  static String themeOf(BuildContext context) => _lookup('theme', context);
  static String uncategorizedOf(BuildContext context) =>
      _lookup('uncategorized', context);
  static String vibrateOf(BuildContext context) => _lookup('vibrate', context);
  static String wakeUpTaskOf(BuildContext context) =>
      _lookup('wakeUpTask', context);
  static String welcomeBodyOf(BuildContext context) =>
      _lookup('welcomeBody', context);
  static String welcomeGoOf(BuildContext context) =>
      _lookup('welcomeGo', context);
  static String welcomeSkipOf(BuildContext context) =>
      _lookup('welcomeSkip', context);
  static String welcomeTitleOf(BuildContext context) =>
      _lookup('welcomeTitle', context);

  static List<String> dayNames(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return [
      byLocale['dayMon']!,
      byLocale['dayTue']!,
      byLocale['dayWed']!,
      byLocale['dayThu']!,
      byLocale['dayFri']!,
      byLocale['daySat']!,
      byLocale['daySun']!,
    ];
  }

  static String repeatLabel(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return byLocale['repeat'] ?? 'Repeat';
  }

  static String repeatDaysLabel(BuildContext context, Alarm alarm) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    if (alarm.repeatDays.isEmpty) return byLocale['labelOnce'] ?? 'Once';
    if (alarm.repeatDays.length == 7) {
      return byLocale['labelEveryDay'] ?? 'Every day';
    }
    final names = dayNames(context);
    if (alarm.repeatDays.length == 5 &&
        !alarm.repeatDays.contains(6) &&
        !alarm.repeatDays.contains(7)) {
      return byLocale['labelWeekdays'] ?? 'Weekdays';
    }
    if (alarm.repeatDays.length == 2 &&
        alarm.repeatDays.contains(6) &&
        alarm.repeatDays.contains(7)) {
      return byLocale['labelWeekends'] ?? 'Weekends';
    }
    return alarm.repeatDays.map((d) => names[d - 1]).join(', ');
  }
}
