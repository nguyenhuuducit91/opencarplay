// OpenCarPlay probe 01 — class/selector tồn tại?
// Dùng:  frida -U -n SpringBoard -l scripts/probe/01-classes.js -q
//        frida -U -n CarPlay     -l scripts/probe/01-classes.js -q
//
// Chỉ ĐỌC runtime. Không hook, không sửa gì.

'use strict';

var TARGETS = {
  // Chuỗi dựng scene mà carplay-cast dùng (RESEARCH.md §2.4) — Q5
  sceneHosting: {
    'SBApplicationController': ['+sharedInstance', '-applicationWithBundleIdentifier:'],
    'SBSceneManagerCoordinator': ['+mainDisplaySceneManager'],
    'SBMainDisplaySceneManager': ['-displayIdentity',
                                  '-_sceneIdentityForApplication:createPrimaryIfRequired:',
                                  '-fetchOrCreateApplicationSceneHandleForRequest:',
                                  '-_layoutStateManager'],
    'SBApplicationSceneHandleRequest': ['+defaultRequestForApplication:sceneIdentity:displayIdentity:'],
    'SBDeviceApplicationSceneEntity': ['-initWithApplicationSceneHandle:'],
    'SBAppViewController': ['-initWithIdentifier:andApplicationSceneEntity:',
                            '-_createSceneViewController', '-appView', '-sceneHandle'],
    'SBApplicationSceneView': ['+defaultDisplayModeAnimationFactory'],
    'SBDeviceApplicationSceneHandle': ['-sceneIfExists'],
    'SBMainDisplaySceneLayoutViewController': ['+mainDisplaySceneLayoutViewController'],
  },
  // Cửa sổ trên màn hình ngoài — Q6
  externalWindow: {
    'UIRootSceneWindow': ['-initWithDisplayConfiguration:'],
    'FBSDisplayConfiguration': ['-initWithCADisplay:isMainDisplay:', '-identity'],
    'FBSDisplayMonitor': ['+sharedInstance', '-displayConfigurations'],
    '_UISystemGestureManager': ['+sharedInstance',
                                '-addGestureRecognizer:toDisplayWithIdentity:'],
    'CADisplay': ['+displays'],
    'AVExternalDevice': ['+currentCarPlayExternalDevice'],
  },
  // Vòng đời / chống suspend
  lifecycle: {
    'FBScene': ['-updateSettings:withTransitionContext:completion:', '-mutableSettings'],
    'FBSceneMonitor': ['-initWithSceneID:', '-invalidate'],
    'SBSuspendedUnderLockManager': ['-_shouldBeBackgroundUnderLockForScene:withSettings:'],
  },
  // Dashboard + chính sách hiển thị app — Q1..Q4
  carplayDashboard: {
    'CARApplication': ['+_newApplicationLibrary'],
    'CARApplicationInfo': [],
    'CARApplicationLaunchInfo': ['+launchInfoForApplication:withActivationSettings:'],
    'CARDashboard': ['-identifierToForegroundAppScenesMap', '-handleEvent:'],
    'CARIconView': [],
    'CARAppDockViewController': ['-_dockButtonPressed:'],
    '_CARDashboardHomeViewController': ['-_handleAppLibraryRefresh', '-setLibrary:'],
    'CRCarPlayAppDeclaration': ['-setSupportsTemplates:', '-setSupportsMaps:',
                                '-setBundleIdentifier:', '-setBundlePath:'],
    'CRCarPlayAppPolicy': [],
    'CRCarPlayAppPolicyEvaluator': [],
    'CRCarPlayAppDenylist': [],
    'CRCarPlayCapabilities': [],
    'CARSessionStatus': ['-initForCarPlayShell', '-session'],
    'CARScreenInfo': [],
    'CARDisplayInfo': [],
    'FBSApplicationLibrary': ['-initWithConfiguration:', '-allInstalledApplications',
                              '-applicationInfoForBundleIdentifier:'],
    'FBSApplicationLibraryConfiguration': ['-setApplicationInfoClass:',
                                           '-setInstalledApplicationFilter:'],
  },
  // Kênh IPC — Q10
  ipc: {
    'NSDistributedNotificationCenter': ['+defaultCenter'],
    'CPDistributedMessagingCenter': ['+centerNamed:'],
    'CPDistributedNotificationCenter': [],
  },
};

function selectorExists(cls, sel) {
  var wrapper = (sel[0] === '+') ? cls : cls.prototype ? cls : cls;
  var name = sel.substring(1);
  try {
    var list = (sel[0] === '+') ? cls.$ownMethods : cls.$ownMethods;
    // $ownMethods trả về dạng "- foo:" / "+ foo:"
    for (var i = 0; i < list.length; i++) {
      var m = list[i].replace(/\s+/g, '');
      if (m === sel[0] + name) return true;
    }
    // thử cả superclass chain
    var sup = cls.$superClass;
    while (sup) {
      var sl = sup.$ownMethods;
      for (var j = 0; j < sl.length; j++) {
        if (sl[j].replace(/\s+/g, '') === sel[0] + name) return 'inherited';
      }
      sup = sup.$superClass;
    }
  } catch (e) { return 'error:' + e.message; }
  return false;
}

console.log('process: ' + Process.id + '  ' + ObjC.classes.NSBundle.mainBundle().bundleIdentifier());
console.log('---------------------------------------------------------------');

var missingClasses = [];
Object.keys(TARGETS).forEach(function (group) {
  console.log('\n### ' + group);
  var spec = TARGETS[group];
  Object.keys(spec).forEach(function (clsName) {
    var cls = ObjC.classes[clsName];
    if (!cls) {
      console.log('  MISS  ' + clsName);
      missingClasses.push(clsName);
      return;
    }
    console.log('  OK    ' + clsName);
    spec[clsName].forEach(function (sel) {
      var r = selectorExists(cls, sel);
      var mark = (r === true) ? '     ok  ' : (r === 'inherited') ? '     inh ' : '     MISS';
      console.log(mark + '  ' + sel);
    });
  });
});

console.log('\n=== TỔNG KẾT ===');
console.log('class thiếu: ' + (missingClasses.length ? missingClasses.join(', ') : '(không)'));
