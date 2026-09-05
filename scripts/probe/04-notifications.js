// OpenCarPlay probe 04 — Q8/Q10: notification nào báo CarPlay connect/disconnect,
// và kênh IPC nào còn hoạt động.
// Dùng:  frida -U -n SpringBoard -l scripts/probe/04-notifications.js
// Cắm rồi rút CarPlay trong lúc script chạy.

'use strict';

// A. Darwin notifications
var notify_post = Module.findExportByName(null, 'notify_post');
if (notify_post) {
  Interceptor.attach(notify_post, {
    onEnter: function (args) {
      var n = args[0].readUtf8String();
      if (/car|Car|CAR|display|screen/i.test(n)) console.log('darwin notify_post: ' + n);
    }
  });
  console.log('[A] đang theo dõi notify_post');
} else {
  console.log('[A] không tìm thấy notify_post');
}

// B. NSNotificationCenter
var NC = ObjC.classes.NSNotificationCenter;
if (NC) {
  Interceptor.attach(NC['- postNotificationName:object:userInfo:'].implementation, {
    onEnter: function (args) {
      try {
        var name = new ObjC.Object(args[2]).toString();
        if (/car/i.test(name)) console.log('NSNotification: ' + name);
      } catch (e) {}
    }
  });
  console.log('[B] đang theo dõi NSNotificationCenter');
}

// C. NSDistributedNotificationCenter còn sống không?
var DNC = ObjC.classes.NSDistributedNotificationCenter;
console.log('[C] NSDistributedNotificationCenter: ' + (DNC ? 'có class' : 'KHÔNG có class'));
if (DNC) {
  try {
    var center = DNC.defaultCenter();
    console.log('    defaultCenter = ' + center);
  } catch (e) {
    console.log('    +defaultCenter ném lỗi: ' + e.message + '  → kênh này KHÔNG dùng được');
  }
}

// D. CPDistributedMessagingCenter
console.log('[D] CPDistributedMessagingCenter: ' +
            (ObjC.classes.CPDistributedMessagingCenter ? 'có class' : 'KHÔNG có class'));

console.log('\nCắm rồi rút CarPlay để xem notification nào xuất hiện. Ctrl-C để dừng.');
