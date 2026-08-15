import 'package:flutter/widgets.dart';
import 'locale_provider.dart';
import '../models/alarm.dart';

const appVersion = '1.3';

class Translations {
  Translations._();

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
      'about': 'About',
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
          'Exact alarm permission not granted. Go to Settings → Apps → Keramika → Battery → No restrictions',
      'pinLock': 'PIN lock',
      'pinDescription': 'Set a PIN to lock the app',
      'setPin': 'Set PIN',
      'changePin': 'Change PIN',
      'removePin': 'Remove PIN',
      'enterPin': 'Enter PIN',
      'confirmPin': 'Confirm PIN',
      'wrongPin': 'Wrong PIN',
      'pinsDoNotMatch': 'PINs do not match',
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
      'habitDaysHint': 'Empty = every day',
      'everyDay': 'Every day',
      'habitNotesBtn': 'Status',
      'habitStatusTitle': 'Reminder',
      'habitStatusHint': 'Quick reminder',
      'habitNotesTitle': 'What you should remember',
      'habitNotesHint': 'Write what matters',
      'habitPinned': 'Habit pinned',
      'habitUnpinned': 'Habit unpinned',
      'habitsSectionGood': 'Useful',
      'habitsSectionBad': 'Harmful',
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
      'welcomeTitle': 'Welcome to Keramika!',
      'welcomeBody':
          'For reliable alarms, please:\n\n1. Disable battery optimization\n2. Enable notifications',
      'welcomeGo': 'Go to settings',
      'welcomeSkip': 'Skip',
      'maxAlarms': 'Max 10 alarms',
      'maxHabits': 'Max 100 habits',
      'maxTasks': 'Max 150 tasks',
      'maxRc': 'Max 1 reality check',
      'maxTimers': 'Max 5 timers',
      'maxCat': 'Max 15 categories',
      'maxCal': 'Max 10000 kcal',
      'maxCalPerMeal': 'Max 10000 kcal per meal',
      'fillAllFields': 'Please fill all fields',
      'mealAdded': 'Meal added successfully',
      'diagnostics': 'Diagnostics',
      'diagAlarmTest': 'Test alarm notification',
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
          'Allow Keramika to draw over other apps to enable the mini window',
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
      'aiGuideHint': 'Ask me',
      'share': 'Share',
      'aiGuideToggle': 'Enable AI guide',
      'aiGuideDesc':
          'A small circle appears next to the “+” button and opens a mini chat.',
      'aiGuideKey': 'Poolside key (optional)',
      'aiGuideKeyHint': 'Paste your Laguna API key',
      'aiGuideKeyNote':
          'Ada uses built-in free models (100 messages for ADA; the rest — FreeLLMPool).',
      'aiGuideKeyNoteProviders':
          'FreeLLMpool, AI Horde, OVHCloud, Pollinations, LLM7 and Kilo',
      'aiGuideKeyNoteTail': '',
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
      'autoExportHourly': 'Save backup to Download/Keramika every hour',
      'autoExportDone': 'Backup saved to Download/Keramika',
      'clearCache': 'Clear cache',
      'clearCacheDesc': 'Free up storage used by temporary files',
      'clearCacheDone': 'Cache cleared!',
      'devMode': 'Developer mode',
      'patchTodos':
          'Remaining to do — autosave, minor tweaks, screen stretch on swipe up',
      'changeSwipeUp': 'Swipe up on the home screen to refresh',
      'changeAdaGuide':
          'AI guide Ada — a mini chat that creates habits, tasks, alarms, reality checks and meals by itself',
      'changeSmoothAnim':
          'Smooth animations everywhere: section transitions, settings, cards, toggles',
      'changeStreakFix': 'Fixed streaks and habit check-offs',
      'changePinBlur': 'PIN lock now blurs the app in recent apps',
      'changeNotifIcon': 'Notification icon — signature K badge',
      'changeAlarmFix': 'Alarms: sounds restored, time picker works with drag',
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
          'If this app helps you, you can thank the developer with a small donation.',
      'supportAuthorHint': 'Opens the donation page in your browser',
      'support': 'Support',
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
      'motivationQuote1': 'Small steps every day lead to big changes.',
      'motivationQuote2': 'Progress, not perfection.',
      'motivationQuote3': 'You are stronger than you think.',
      'motivationQuote4': 'Every expert was once a beginner.',
      'motivationQuote5': 'Consistency beats intensity.',
      'motivationQuote6': 'Focus on progress, not perfection.',
      'motivationQuote7': 'You are capable of amazing things.',
      'motivationQuote8': 'One day at a time.',
      'motivationQuote9': 'Believe in yourself.',
      'motivationQuote10': 'Dream big, start small.',
      'motivationQuote11': 'Every moment is a fresh beginning.',
      'motivationQuote12': 'Your only limit is you.',
      'motivationQuote13': 'Make today count.',
      'motivationQuote14': 'Small wins add up to big results.',
      'motivationQuote15': 'Keep going, you are almost there.',
      'motivationQuote16': 'Discipline is freedom.',
      'motivationQuote17':
          'You don\'t need to see the whole staircase — just take the first step.',
      'motivationQuote18':
          'The pain of discipline is less than the pain of regret.',
      'motivationQuote19':
          'Every habit you build is a vote for the person you want to become.',
      'motivationQuote20':
          'Success is the sum of small efforts repeated daily.',
      'motivationQuote21':
          'Don’t stare at the clock. Do what clocks do — keep going.',
      'motivationQuote22':
          'Your future self is watching you right now through memories.',
      'motivationQuote23': 'A year from now you wish you had started today.',
      'motivationQuote24':
          'The only bad workout is the one that didn’t happen.',
      'motivationQuote25':
          'Small daily improvements are the key to staggering long-term results.',
      'motivationQuote26': 'You are one decision away from a different life.',
      'motivationQuote27':
          'The best time to plant a tree was 20 years ago. The second best is now.',
      'motivationQuote28':
          'Your body can handle almost anything. It’s your mind you have to convince.',
      'motivationQuote29':
          'Don’t stop when you’re tired. Stop when you’re done.',
      'motivationQuote30':
          'Every day is a fresh start. No grudges with yesterday.',
      'motivationQuote31':
          'You are going through a struggle that is forging strength for tomorrow.',
      'motivationQuote32': 'If it was easy, everyone would do it.',
      'motivationQuote33':
          'Focus on progress, not perfection. One percent better every day wins.',
      'motivationQuote34':
          'You don’t need motivation — you need discipline and a plan.',
      'motivationQuote35':
          'The pain of staying the same is greater than the pain of change.',
      'motivationQuote36': 'Dreams don’t work unless you do.',
      'motivationQuote37':
          'Small actions, multiplied daily, lead to massive change.',
      'motivationQuote38': 'Be proud of how far you have come. Keep going.',
      'motivationQuote39': 'Effort today is strength tomorrow.',
      'motivationQuote40': 'You’re not behind. You’re on your own path.',
      'motivationQuote41': 'Action cures fear. Inaction feeds it.',
      'motivationQuote42': 'The hardest step is the first one. Take it.',
      'motivationQuote43':
          'Consistency turns ordinary effort into outstanding results.',
      'motivationQuote44': 'A goal without a plan is just a wish.',
      'motivationQuote45': 'Where you are now is not the endpoint.',
      'motivationQuote46':
          'Your only competitor is the person you were yesterday.',
      'motivationQuote47':
          'Habits are the compound interest of self-improvement.',
      'motivationQuote48': 'Success doesn’t come to you — you go to it.',
      'motivationQuote49': 'Fall seven times, stand up eight.',
      'motivationQuote50':
          'You’ve survived 100% of your hardest days. You’ll survive this one too.',
      'motivationQuote51':
          'A seed planted today will become the tree you rest under tomorrow.',
      'motivationQuote52':
          'Your habits shape your character. Your character shapes your destiny.',
      'motivationQuote53':
          'Stop waiting for the perfect moment. Take the moment and make it perfect.',
      'motivationQuote54': 'Small disciplines are gateways to great abilities.',
      'motivationQuote55': 'Mind is everything. What you think, you become.',
      'motivationQuote56':
          'You can’t go back and change the beginning, but you can start where you are.',
      'motivationQuote57': 'The road to success is always under construction.',
      'motivationQuote58': 'Great things never come from comfort zones.',
      'motivationQuote59': 'Believe you can and you’re halfway there.',
      'motivationQuote60': 'Every master was once a disaster.',
      'motivationQuote61': 'Don\'t count the days. Make the days count.',
      'motivationQuote62':
          'A journey of a thousand miles begins with a single step.',
      'motivationQuote63':
          'Hard work beats talent when talent doesn’t work hard.',
      'motivationQuote64':
          'The only limit to your impact is your imagination and commitment.',
      'motivationQuote65': 'Focus on productivity, not just activity.',
      'motivationQuote66':
          'You’re not a victim of your habits — you’re the architect.',
      'motivationQuote67': 'Do today what your future self will thank you for.',
      'motivationQuote68':
          'The difference between ordinary and extraordinary is a little extra effort.',
      'motivationQuote69': 'You don’t have to be extreme — just consistent.',
      'motivationQuote70': 'Your potential is unlimited. Your excuses are not.',
      'motivationQuote71':
          'Stop comparing your chapter 1 to someone else’s chapter 20.',
      'motivationQuote72':
          'The pain of discipline weighs ounces. The pain of regret weighs tons.',
      'motivationQuote73':
          'Small habits, repeated daily, transform life for years ahead.',
      'motivationQuote74': 'Don’t seek motivation. Create it by showing up.',
      'motivationQuote75': 'A goal is a dream with a deadline. Set yours.',
      'motivationQuote76':
          'Discipline is choosing what you want most over what you want now.',
      'motivationQuote77':
          'The only one who can beat you is you. And yesterday was their best day.',
      'motivationQuote78':
          'Success is built in private moments when nobody is watching.',
      'motivationQuote79':
          'If you keep doing what you’ve always done, you’ll keep getting what you’ve always got.',
      'motivationQuote80':
          'Don’t pray for an easy life. Pray for the strength to endure a hard one.',
      'motivationQuote81':
          'Every champion was once a contender that didn’t quit.',
      'motivationQuote82':
          'The future depends on what you do today, not tomorrow.',
      'motivationQuote83':
          'You become what you repeat. Make your repetitions meaningful.',
      'motivationQuote84': 'Courage doesn’t remove fear — it acts despite it.',
      'motivationQuote85':
          'When you feel like quitting, remember why you started.',
      'motivationQuote86':
          'No one else is going to build your dreams. Get to work.',
      'motivationQuote87': 'Rest, but don’t quit.',
      'motivationQuote88': 'Consistency turns luck into design.',
      'motivationQuote89': 'The harder you train, the luckier you get.',
      'motivationQuote90': 'Your daily habits are the architecture of destiny.',
      'areYouSure': 'Are you sure?',
      'streakResetDone': 'Streak reset',
      'openSettings': 'Open settings',
      'italic': 'Italic',
      'berserkCardTitle': 'MAXIMUM BERSERK LEVEL UPGRADE',
      'berserkCardSubtitle':
          'Hold the “+” on any screen — a mode of personal power and focus opens.',
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
      'about': 'О приложении',
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
          'Точные будильники не разрешены. Перейди в Настройки → Приложения → Keramika → Батарея → Без ограничений',
      'pinLock': 'PIN-код',
      'pinDescription': 'Поставьте PIN, чтобы заблокировать приложение',
      'setPin': 'Поставить PIN',
      'changePin': 'Сменить PIN',
      'removePin': 'Убрать PIN',
      'enterPin': 'Введите PIN',
      'confirmPin': 'Подтвердите PIN',
      'wrongPin': 'Неверный PIN',
      'pinsDoNotMatch': 'PIN-коды не совпадают',
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
      'habitDaysHint': 'Пусто = каждый день',
      'everyDay': 'Каждый день',
      'habitNotesBtn': 'Статус',
      'habitStatusTitle': 'Напоминание',
      'habitStatusHint': 'Короткая напоминалка',
      'habitNotesTitle': 'Что нужно запомнить',
      'habitNotesHint': 'Запиши, что важно',
      'habitPinned': 'Привычка закреплена',
      'habitUnpinned': 'Привычка откреплена',
      'habitsSectionGood': 'Полезные',
      'habitsSectionBad': 'Вредные',
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
      'welcomeTitle': 'Добро пожаловать в Keramika!',
      'welcomeBody':
          'Для надёжных будильников:\n\n1. Отключите оптимизацию батареи\n2. Включите уведомления',
      'welcomeGo': 'К настройкам',
      'welcomeSkip': 'Пропустить',
      'maxAlarms': 'Максимум 10 будильников',
      'maxHabits': 'Максимум 100 привычек',
      'maxTasks': 'Максимум 150 задач',
      'maxRc': 'Максимум 1 проверка',
      'maxTimers': 'Максимум 5 таймеров',
      'maxCat': 'Максимум 15 категорий',
      'maxCal': 'Максимум 10000 ккал',
      'maxCalPerMeal': 'Максимум 10000 ккал за приём',
      'fillAllFields': 'Пожалуйста, заполните все поля',
      'mealAdded': 'Приём пищи успешно добавлен',
      'diagnostics': 'Диагностика',
      'diagAlarmTest': 'Тест уведомления будильника',
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
          'Разреши Keramika показывать поверх других приложений, чтобы включить мини-окошко',
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
      'aiGuideHint': 'Спроси меня',
      'share': 'Поделиться',
      'aiGuideToggle': 'Включить проводника',
      'aiGuideDesc':
          'Рядом с кнопкой «+» появится мелкий кружок — он открывает мини-чат.',
      'aiGuideKey': 'Ключ Poolside (необязательно)',
      'aiGuideKeyHint': 'Вставь свой ключ Laguna',
      'aiGuideKeyNote':
          'Ада использует встроенные бесплатные модели (100 сообщений на ADA, остальное — FreeLLMPool).',
      'aiGuideKeyNoteProviders':
          'FreeLLMpool, AI Horde, OVHCloud, Pollinations, LLM7 и Kilo',
      'aiGuideKeyNoteTail': '',
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
      'autoExportHourly': 'Сохранять бэкап в Загрузки/Keramika каждый час',
      'autoExportDone': 'Бэкап сохранён в Загрузки/Keramika',
      'clearCache': 'Очистить кэш',
      'clearCacheDesc': 'Освободить место, занятое временными файлами',
      'clearCacheDone': 'Кэш очищен!',
      'devMode': 'Режим разработчика',
      'patchTodos':
          'Осталось сделать — автосохранение, мелкие доработки, натяжение экрана свайпом вверх',
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
          'Если приложение помогает — можешь отблагодарить разработчика небольшим донатом.',
      'supportAuthorHint': 'Откроет страницу благодарности в браузере',
      'support': 'Поддержать',
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
      'motivationQuote1':
          'Маленькие шаги каждый день ведут к большим переменам.',
      'motivationQuote2': 'Прогресс, а не совершенство.',
      'motivationQuote3': 'Ты сильнее, чем думаешь.',
      'motivationQuote4': 'Каждый эксперт когда-то был новичком.',
      'motivationQuote5': 'Постоянство бьёт интенсивность.',
      'motivationQuote6': 'Фокус на прогрессе, а не на совершенстве.',
      'motivationQuote7': 'Ты способен на удивительные вещи.',
      'motivationQuote8': 'Один день за раз.',
      'motivationQuote9': 'Верь в себя.',
      'motivationQuote10': 'Мечтай по-крупному, начинай по-маленькому.',
      'motivationQuote11': 'Каждый момент — свежее начало.',
      'motivationQuote12': 'Твой единственный предел — ты сам.',
      'motivationQuote13': 'Сделай сегодняшний день значимым.',
      'motivationQuote14':
          'Маленькие победы складываются в большие результаты.',
      'motivationQuote15': 'Продолжай, ты уже почти у цели.',
      'motivationQuote16': 'Дисциплина — это свобода.',
      'motivationQuote17':
          'Не нужно видеть всю лестницу — просто сделай первый шаг.',
      'motivationQuote18': 'Боль от дисциплины меньше боли от сожалений.',
      'motivationQuote19':
          'Каждая привычка, которую ты строишь, — голос за того, кем хочешь стать.',
      'motivationQuote20':
          'Успех — это сумма маленьких усилий, повторённых ежедневно.',
      'motivationQuote21':
          'Не смотри на часы. Делай то, что они делают, — продолжай идти.',
      'motivationQuote22':
          'Твоё будущее «я» сейчас смотрит на тебя через воспоминания.',
      'motivationQuote23': 'Через год ты пожалеешь, что не начал сегодня.',
      'motivationQuote24':
          'Единственное плохое упражнение — то, которое не было сделано.',
      'motivationQuote25':
          'Маленькие ежедневные улучшения — ключ к потрясающим долгосрочным результатам.',
      'motivationQuote26': 'Ты на одном решении от другой жизни.',
      'motivationQuote27':
          'Лучшее время посадить дерево было 20 лет назад. Второе лучшее — сейчас.',
      'motivationQuote28':
          'Твоё тело выдержит почти всё. Нужно убедить в этом разум.',
      'motivationQuote29':
          'Не останавливайся, когда устал. Остановись, когда закончил.',
      'motivationQuote30':
          'Каждый день — свежее начало. Без обид на вчерашний день.',
      'motivationQuote31':
          'Сейчас ты проходишь через борьбу, которая закаляет силу для завтра.',
      'motivationQuote32': 'Если бы это было легко, это делали бы все.',
      'motivationQuote33':
          'Фокус на прогрессе, а не совершенстве. Один процент лучше каждый день — это победа.',
      'motivationQuote34':
          'Тебе не нужна мотивация — тебе нужны дисциплина и план.',
      'motivationQuote35':
          'Боль от прежнего состояния больше, чем боль от перемен.',
      'motivationQuote36': 'Мечты не работают, пока не работаешь ты.',
      'motivationQuote37':
          'Маленькие действия, умноженные ежедневно, приводят к массовым переменам.',
      'motivationQuote38': 'Гордись тем, как далеко ты зашёл. Продолжай.',
      'motivationQuote39': 'Усилия сегодня — сила завтра.',
      'motivationQuote40': 'Ты не отстаёшь. Ты на своём пути.',
      'motivationQuote41': 'Действие лечит страх. Бездействие кормит его.',
      'motivationQuote42': 'Самый трудный шаг — первый. Сделай его.',
      'motivationQuote43':
          'Постоянство превращает обычные усилия в выдающиеся результаты.',
      'motivationQuote44': 'Цель без плана — просто желание.',
      'motivationQuote45': 'Твоё текущее положение — не конечная точка.',
      'motivationQuote46': 'Единственный конкурент — тот, кем ты был вчера.',
      'motivationQuote47':
          'Привычки — это сложные проценты самосовершенствования.',
      'motivationQuote48': 'Успех не приходит к тебе — ты идёшь к нему.',
      'motivationQuote49': 'Падай семь раз — вставай восемь.',
      'motivationQuote50':
          'Ты пережил(а) 100% самых тяжёлых дней, которые у тебя были.',
      'motivationQuote51':
          'Семя, посаженное сегодня, вырастет в дерево, под которым ты отдохнёшь завтра.',
      'motivationQuote52':
          'Твои привычки формируют характер. Характер формирует судьбу.',
      'motivationQuote53':
          'Перестань ждать идеального момента. Возьми момент и сделай его идеальным.',
      'motivationQuote54': 'Малые дисциплины — ворота к великим способностям.',
      'motivationQuote55': 'Разум — это всё. Что ты думаешь, тем становишься.',
      'motivationQuote56':
          'Нельзя вернуться и изменить начало, но можно начать с того места, где ты есть.',
      'motivationQuote57': 'Дорога к успеху всегда в строительстве.',
      'motivationQuote58': 'Великие вещи никогда не приходят из зон комфорта.',
      'motivationQuote59': 'Поверь, что можешь, — и уже на полпути.',
      'motivationQuote60': 'Каждый мастер когда-то был катастрофой.',
      'motivationQuote61': 'Не считай дни. Заставляй дни считаться.',
      'motivationQuote62':
          'Путешествие в тысячу миль начинается с одного шага.',
      'motivationQuote63':
          'Тяжёлая работа бьёт талант, когда талант не работает.',
      'motivationQuote64':
          'Единственный предел твоего влияния — воображение и обязательства.',
      'motivationQuote65': 'Фокусируйся на продуктивности, а не на занятости.',
      'motivationQuote66': 'Ты не жертва своих привычек — ты архитектор.',
      'motivationQuote67':
          'Сделай сегодня то, за что скажет спасибо твоё будущее «я».',
      'motivationQuote68':
          'Разница между обычным и выдающимся — немного дополнительных усилий.',
      'motivationQuote69': 'Не нужно быть экстремальным — просто постоянным.',
      'motivationQuote70': 'Твой потенциал безграничен. Твои оправдания — нет.',
      'motivationQuote71':
          'Перестань сравнивать свою главу 1 с главой 20 другого.',
      'motivationQuote72':
          'Боль дисциплины весит унции. Боль сожалений — тонны.',
      'motivationQuote73':
          'Малые привычки, повторяемые каждый день, меняют жизнь на годы вперёд.',
      'motivationQuote74': 'Не ищи мотивацию. Создавай её, появляясь.',
      'motivationQuote75': 'Цель — это мечта с дедлайном. Назначь свой.',
      'motivationQuote76':
          'Дисциплина выбирает то, чего хочешь больше всего, а не то, чего хочешь прямо сейчас.',
      'motivationQuote77':
          'Единственный, кто может победить тебя, — это ты. А вчера был их лучший день.',
      'motivationQuote78':
          'Успех строится в приватные моменты, когда никто не смотрит.',
      'motivationQuote79':
          'Если продолжаешь делать одно и то же — получаешь одно и то же.',
      'motivationQuote80':
          'Не моли об лёгкой жизни — моли о силе выдержать трудную.',
      'motivationQuote81':
          'Каждый чемпион когда-то был соперником, который не сдался.',
      'motivationQuote82':
          'Будущее зависит от того, что ты делаешь сегодня, а не завтра.',
      'motivationQuote83':
          'Ты становишься тем, что повторяешь. Делай повторения значимыми.',
      'motivationQuote84':
          'Смелость не убирает страх — она действует несмотря на него.',
      'motivationQuote85': 'Когда захочется сдаться, вспомни, почему начал.',
      'motivationQuote86': 'Никто другой не построит твои мечты. Работай.',
      'motivationQuote87': 'Отдыхай, но не сдавайся.',
      'motivationQuote88': 'Постоянство превращает удачу в дизайн.',
      'motivationQuote89':
          'Чем тяжелее тренируешься, тем удачливее становишься.',
      'motivationQuote90': 'Твои ежедневные привычки — архитектура судьбы.',
      'areYouSure': 'Уверены?',
      'streakResetDone': 'Стрик сброшен',
      'openSettings': 'Открыть настройки',
      'italic': 'Курсив',
      'berserkCardTitle': 'МАКСИМАЛЬНЫЙ АПГРЕЙД УРОВНЯ BERSERK',
      'berserkCardSubtitle':
          'Зажми «плюс» на любом экране — откроется режим личной силы и фокуса.',
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
      'about': 'À propos',
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
          'Autorisation d’alarme exacte refusée. Allez dans Paramètres → Applications → Keramika → Batterie → Aucune restriction',
      'pinLock': 'Code PIN',
      'pinDescription': 'Définir un PIN pour verrouiller l’application',
      'setPin': 'Définir le PIN',
      'changePin': 'Changer le PIN',
      'removePin': 'Supprimer le PIN',
      'enterPin': 'Saisir le PIN',
      'confirmPin': 'Confirmer le PIN',
      'wrongPin': 'PIN incorrect',
      'pinsDoNotMatch': 'Les PIN ne correspondent pas',
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
      'habitDaysHint': 'Vide = tous les jours',
      'everyDay': 'Tous les jours',
      'habitNotesBtn': 'Statut',
      'habitStatusTitle': 'À retenir',
      'habitStatusHint': 'Petit rappel',
      'habitNotesTitle': 'Ce qu’il faut retenir',
      'habitNotesHint': 'Notez ce qui compte',
      'habitPinned': 'Habitude épinglée',
      'habitUnpinned': 'Habitude désépinglée',
      'habitsSectionGood': 'Utiles',
      'habitsSectionBad': 'Nuisibles',
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
      'welcomeTitle': 'Bienvenue dans Keramika !',
      'welcomeBody':
          'Pour des alarmes fiables :\n\n1. Désactivez l’optimisation de la batterie\n2. Activez les notifications',
      'welcomeGo': 'Aller aux paramètres',
      'welcomeSkip': 'Passer',
      'maxAlarms': 'Maximum 10 alarmes',
      'maxHabits': 'Maximum 100 habitudes',
      'maxTasks': 'Maximum 150 tâches',
      'maxRc': 'Maximum 1 vérification',
      'maxTimers': 'Maximum 5 minuteurs',
      'maxCat': 'Maximum 15 catégories',
      'maxCal': 'Maximum 10000 kcal',
      'maxCalPerMeal': 'Maximum 10000 kcal par repas',
      'fillAllFields': 'Veuillez remplir tous les champs',
      'mealAdded': 'Repas ajouté avec succès',
      'diagnostics': 'Diagnostics',
      'diagAlarmTest': 'Tester la notification d’alarme',
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
          'Autorisez Keramika à s’afficher par-dessus les autres apps pour activer la mini-fenêtre',
      'aiTrackingNoPerm':
          'Le suivi Ada est activé, mais les notifications sont bloquées — autorisez-les dans les réglages',
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
      'aiGuideHint': 'Demande-moi',
      'share': 'Partager',
      'aiGuideToggle': 'Activer le guide IA',
      'aiGuideDesc':
          'Un petit cercle apparaît à côté du bouton « + » et ouvre un mini-chat.',
      'aiGuideKey': 'Clé Poolside (optionnelle)',
      'aiGuideKeyHint': 'Collez votre clé Laguna',
      'aiGuideKeyNote':
          'Ada utilise des modèles gratuits intégrés (100 messages pour ADA, le reste — FreeLLMPool).',
      'aiGuideKeyNoteProviders':
          'FreeLLMpool, AI Horde, OVHCloud, Pollinations, LLM7 et Kilo',
      'aiGuideKeyNoteTail': '',
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
          'Enregistrer une sauvegarde dans Téléchargements/Keramika chaque heure',
      'autoExportDone': 'Sauvegarde enregistrée dans Téléchargements/Keramika',
      'clearCache': 'Vider le cache',
      'clearCacheDesc': 'Libérer l’espace des fichiers temporaires',
      'clearCacheDone': 'Cache vidé !',
      'devMode': 'Mode développeur',
      'patchTodos':
          'À faire — sauvegarde automatique, petites améliorations, étirement de l\'écran en balayant vers le haut',
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
          'Si cette application vous aide, vous pouvez remercier le développeur avec un petit don.',
      'supportAuthorHint': 'Ouvre la page de remerciement dans le navigateur',
      'support': 'Soutenir',
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
      'motivationQuote1':
          'Les petits pas quotidiens mènent à de grands changements.',
      'motivationQuote2': 'Le progrès, pas la perfection.',
      'motivationQuote3': 'Vous êtes plus fort que vous ne le pensez.',
      'motivationQuote4': 'Chaque expert a un jour été débutant.',
      'motivationQuote5': 'La constance bat l’intensité.',
      'motivationQuote6':
          'Concentrez-vous sur le progrès, pas sur la perfection.',
      'motivationQuote7': 'Vous êtes capable de choses étonnantes.',
      'motivationQuote8': 'Un jour à la fois.',
      'motivationQuote9': 'Croyez en vous.',
      'motivationQuote10': 'Rêvez grand, commencez petit.',
      'motivationQuote11': 'Chaque instant est un nouveau départ.',
      'motivationQuote12': 'Votre seule limite, c’est vous.',
      'motivationQuote13': 'Faites que la journée compte.',
      'motivationQuote14':
          'Les petites victoires s’accumulent en grands résultats.',
      'motivationQuote15': 'Continuez, vous y êtes presque.',
      'motivationQuote16': 'La discipline, c’est la liberté.',
      'motivationQuote17':
          'Pas besoin de voir tout l’escalier — faites juste le premier pas.',
      'motivationQuote18':
          'La douleur de la discipline est moindre que celle du regret.',
      'motivationQuote19':
          'Chaque habitude que vous bâtissez est un vote pour la personne que vous voulez devenir.',
      'motivationQuote20':
          'Le succès est la somme de petits efforts répétés chaque jour.',
      'motivationQuote21':
          'Ne fixez pas l’horloge. Faites ce qu’elle fait — continuez.',
      'motivationQuote22': 'Votre futur vous regarde à travers les souvenirs.',
      'motivationQuote23':
          'Dans un an, vous regretterez de ne pas avoir commencé aujourd’hui.',
      'motivationQuote24':
          'Le seul mauvais entraînement est celui qui n’a pas eu lieu.',
      'motivationQuote25':
          'Les petites améliorations quotidiennes font les résultats impressionnants sur le long terme.',
      'motivationQuote26': 'Vous êtes à une décision d’une autre vie.',
      'motivationQuote27':
          'Le meilleur moment pour planter un arbre était il y a 20 ans. Le deuxième meilleur, c’est maintenant.',
      'motivationQuote28':
          'Votre corps peut supporter presque tout. Il faut convaincre votre esprit.',
      'motivationQuote29':
          'Ne vous arrêtez pas quand vous êtes fatigué. Arrêtez-vous quand c’est terminé.',
      'motivationQuote30':
          'Chaque jour est un nouveau départ. Pas de rancune contre hier.',
      'motivationQuote31':
          'Vous traversez une lutte qui forge la force de demain.',
      'motivationQuote32': 'Si c’était facile, tout le monde le ferait.',
      'motivationQuote33':
          'Cap sur le progrès, pas la perfection. Un pour cent mieux chaque jour suffit.',
      'motivationQuote34':
          'Vous n’avez pas besoin de motivation — il vous faut de la discipline et un plan.',
      'motivationQuote35':
          'La douleur de ne pas changer est plus grande que celle du changement.',
      'motivationQuote36': 'Les rêves ne marchent que si vous travaillez.',
      'motivationQuote37':
          'Les petites actions multipliées chaque jour mènent à de grands changements.',
      'motivationQuote38': 'Soyez fier du chemin parcouru. Continuez.',
      'motivationQuote39': 'L’effort d’aujourd’hui est la force de demain.',
      'motivationQuote40':
          'Vous n’êtes pas en retard. Vous êtes sur votre propre chemin.',
      'motivationQuote41': 'L’action soigne la peur. L’inaction la nourrit.',
      'motivationQuote42': 'Le pas le plus dur est le premier. Faites-le.',
      'motivationQuote43':
          'La constance transforme un effort ordinaire en un résultat remarquable.',
      'motivationQuote44': 'Un objectif sans plan n’est qu’un souhait.',
      'motivationQuote45':
          'L’endroit où vous êtes n’est pas la destination finale.',
      'motivationQuote46':
          'Votre seul concurrent est la personne que vous étiez hier.',
      'motivationQuote47':
          'Les habitudes sont les intérêts composés de la amélioration de soi.',
      'motivationQuote48':
          'Le succès ne vient pas à vous — vous allez vers lui.',
      'motivationQuote49': 'Tombez sept fois, relevez-vous huit.',
      'motivationQuote50':
          'Vous avez surmonté 100 % de vos jours les plus durs.',
      'motivationQuote51':
          'La graine plantée aujourd’hui deviendra l’arbre sous lequel vous vous reposerez demain.',
      'motivationQuote52':
          'Vos habitudes forgent votre caractère. Le caractère forge votre destin.',
      'motivationQuote53':
          'Arrêtez d’attendre le moment parfait. Prenez le moment et rendez-le parfait.',
      'motivationQuote54':
          'Les petites disciplines ouvrent les grandes capacités.',
      'motivationQuote55':
          'Le mental est tout. Ce que vous pensez, vous le devenez.',
      'motivationQuote56':
          'Vous ne pouvez pas revenir changer le début, mais vous pouvez commencer là où vous êtes.',
      'motivationQuote57': 'La route du succès est toujours en chantier.',
      'motivationQuote58':
          'Les grandes choses ne viennent jamais des zones de confort.',
      'motivationQuote59': 'Croyez que vous pouvez et vous êtes à mi-chemin.',
      'motivationQuote60': 'Chaque maître a un jour été un désastre.',
      'motivationQuote61':
          'Ne comptez pas les jours. Faites que les jours comptent.',
      'motivationQuote62':
          'Un voyage de mille lieues commence par un seul pas.',
      'motivationQuote63':
          'Le travail acharné bat le talent quand le talent ne travaille pas.',
      'motivationQuote64':
          'La seule limite de votre impact est votre imagination et votre engagement.',
      'motivationQuote65':
          'Concentrez-vous sur la productivité, pas seulement l’activité.',
      'motivationQuote66':
          'Vous n’êtes pas victime de vos habitudes — vous en êtes l’architecte.',
      'motivationQuote67':
          'Faites aujourd’hui ce dont votre futur vous remerciera.',
      'motivationQuote68':
          'La différence entre l’ordinaire et l’extraordinaire, c’est un peu plus d’effort.',
      'motivationQuote69': 'Pas besoin d’être extrême — juste constant.',
      'motivationQuote70':
          'Votre potentiel est sans limites. Vos excuses, non.',
      'motivationQuote71':
          'Arrêtez de comparer votre chapitre 1 au chapitre 20 d’un autre.',
      'motivationQuote72':
          'La douleur de la discipline pèse des grammes. Celle du regret pèse des tonnes.',
      'motivationQuote73':
          'Les petites habitudes, répétées chaque jour, changent la vie pour des années.',
      'motivationQuote74':
          'Ne cherchez pas la motivation. Créez-la en vous montrant.',
      'motivationQuote75':
          'Un objectif est un rêve avec une échéance. Fixez la vôtre.',
      'motivationQuote76':
          'La discipline choisit ce que vous voulez le plus, pas ce que vous voulez maintenant.',
      'motivationQuote77':
          'Le seul capable de vous battre, c’est vous. Et hier était leur meilleur jour.',
      'motivationQuote78':
          'Le succès se construit dans les instants privés où personne ne regarde.',
      'motivationQuote79':
          'Si vous continuez à faire la même chose, vous obtenez la même chose.',
      'motivationQuote80':
          'Ne priez pas pour une vie facile. Priez pour la force d’en supporter une difficile.',
      'motivationQuote81':
          'Chaque champion a été un concurrent qui n’a pas abandonné.',
      'motivationQuote82':
          'Le futur dépend de ce que vous faites aujourd’hui, pas demain.',
      'motivationQuote83':
          'Vous devenez ce que vous répétez. Rendez vos répétitions significatives.',
      'motivationQuote84':
          'Le courage ne supprime pas la peur — il agit malgré elle.',
      'motivationQuote85':
          'Quand vous voulez abandonner, souvenez-vous pourquoi vous avez commencé.',
      'motivationQuote86':
          'Personne d’autre ne construira vos rêves. Travaillez.',
      'motivationQuote87': 'Reposez-vous, mais n’abandonnez pas.',
      'motivationQuote88': 'La constance transforme la chance en design.',
      'motivationQuote89':
          'Plus vous vous entraînez dur, plus vous avez de la chance.',
      'motivationQuote90':
          'Vos habitudes quotidiennes sont l’architecture du destin.',
      'areYouSure': 'Êtes-vous sûr ?',
      'streakResetDone': 'Série réinitialisée',
      'openSettings': 'Ouvrir les paramètres',
      'italic': 'Italique',
      'berserkCardTitle': 'MISE À NIVEAU MAXIMALE DU NIVEAU BERSERK',
      'berserkCardSubtitle':
          'Maintenez le « + » sur n’importe quel écran — un mode de force personnelle et de concentration s’ouvre.',
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
    },
  };

  static String _lookup(String key, BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return byLocale[key] ?? key;
  }

  static String t(String key, BuildContext context, [String? fallback]) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return _emdash(byLocale[key] ?? fallback ?? key);
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
