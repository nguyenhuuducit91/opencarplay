// OpenCarPlay probe 03 — Q7: lấy thông tin màn hình xe bằng cách nào trên iOS 18.6?
// Dùng:  frida -U -n SpringBoard -l scripts/probe/03-display.js -q     (khi ĐANG cắm CarPlay)

'use strict';

function tryBlock(label, fn) {
  try { fn(); } catch (e) { console.log(label + ': lỗi — ' + e.message); }
}

console.log('=== A. FBSDisplayMonitor ===');
tryBlock('FBSDisplayMonitor', function () {
  var M = ObjC.classes.FBSDisplayMonitor;
  if (!M) { console.log('  MISS FBSDisplayMonitor'); return; }
  var mon = M.sharedInstance ? M.sharedInstance() : null;
  if (!mon) { console.log('  không có +sharedInstance'); return; }
  var confs = mon.displayConfigurations();
  console.log('  số display: ' + confs.count());
  for (var i = 0; i < confs.count(); i++) {
    var c = confs.objectAtIndex_(i);
    console.log('  [' + i + '] ' + c.toString());
    ['identity', 'name', 'displayType', 'isMainDisplay', 'pixelSize', 'pointSize', 'scale']
      .forEach(function (k) {
        try { if (c[k]) console.log('        ' + k + ' = ' + c[k]()); } catch (e) {}
      });
  }
});

console.log('\n=== B. CADisplay ===');
tryBlock('CADisplay', function () {
  var D = ObjC.classes.CADisplay;
  if (!D) { console.log('  MISS CADisplay'); return; }
  var ds = D.displays();
  for (var i = 0; i < ds.count(); i++) {
    var d = ds.objectAtIndex_(i);
    console.log('  [' + i + '] uniqueId=' + d.uniqueId() + '  name=' + (d.name ? d.name() : '?'));
  }
});

console.log('\n=== C. AVExternalDevice (cách của carplay-cast) ===');
tryBlock('AVExternalDevice', function () {
  var A = ObjC.classes.AVExternalDevice;
  if (!A) { console.log('  MISS AVExternalDevice'); return; }
  var dev = A.currentCarPlayExternalDevice();
  console.log('  currentCarPlayExternalDevice = ' + dev);
  if (dev && !dev.isNull()) console.log('  screenIDs = ' + dev.screenIDs());
});

console.log('\n=== D. CARScreenInfo / CARDisplayInfo (đường mới) ===');
['CARScreenInfo', 'CARDisplayInfo', 'CARSession', 'CARSessionStatus'].forEach(function (n) {
  console.log('  ' + (ObjC.classes[n] ? 'OK   ' : 'MISS ') + n);
});

console.log('\n=== E. UIScreen ===');
tryBlock('UIScreen', function () {
  var screens = ObjC.classes.UIScreen.screens();
  console.log('  UIScreen.screens count = ' + screens.count());
  for (var i = 0; i < screens.count(); i++) {
    var s = screens.objectAtIndex_(i);
    var isCar = '?';
    try { isCar = s._isCarScreen(); } catch (e) { isCar = '(không có _isCarScreen)'; }
    console.log('  [' + i + '] bounds=' + s.bounds() + ' scale=' + s.scale() + ' carScreen=' + isCar);
  }
});
