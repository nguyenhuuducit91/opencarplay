// OpenCarPlay probe 02 — Q1..Q4: iOS 18 quyết định app nào lên dashboard bằng cách nào?
// Dùng:  frida -U -n CarPlay -l scripts/probe/02-carplay-policy.js
// Cắm CarPlay, mở dashboard, quan sát thứ tự lời gọi.
//
// Chỉ TRACE — không thay đổi giá trị trả về.

'use strict';

var WATCH = ['CRCarPlayAppPolicyEvaluator', 'CRCarPlayAppPolicy', 'CRCarPlayAppDeclaration',
             'CRCarPlayAppDenylist', 'CARApplication', 'CARApplicationInfo'];

function shortDesc(v) {
  try {
    if (v === null || v.isNull()) return 'nil';
    var o = new ObjC.Object(v);
    var s = o.toString();
    return s.length > 120 ? s.substring(0, 120) + '…' : s;
  } catch (e) { return String(v); }
}

WATCH.forEach(function (clsName) {
  var cls = ObjC.classes[clsName];
  if (!cls) { console.log('MISS class ' + clsName); return; }
  console.log('=== hook ' + clsName + ' (' + cls.$ownMethods.length + ' methods) ===');
  cls.$ownMethods.forEach(function (sel) {
    // bỏ qua accessor rác để log đọc được
    if (/^-\s*\.cxx_/.test(sel)) return;
    try {
      var impl = cls[sel];
      Interceptor.attach(impl.implementation, {
        onEnter: function (args) {
          this.sel = sel;
          var extra = '';
          if (sel.indexOf(':') !== -1) extra = ' arg2=' + shortDesc(args[2]);
          console.log('→ [' + clsName + ' ' + sel + ']' + extra);
        },
        onLeave: function (ret) {
          if (/policy|Policy|canDisplay|supported|capable|declaration/i.test(this.sel)) {
            console.log('   ← ' + this.sel + ' = ' + ret + ' (' + shortDesc(ret) + ')');
          }
        }
      });
    } catch (e) { /* method không hook được — bỏ qua */ }
  });
});

console.log('\nĐang trace. Mở/đóng dashboard CarPlay để thu thập. Ctrl-C để dừng.');
