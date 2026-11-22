// The library's picture process on Android (docs/plans/2026-11-22-library-pictures-robust.md): a service in its own
// process (android:process=":pictures") that makes one ROM's card picture with the same native code
// (LibraryThumbs::makeRomPictureFile). A core that crashes or hangs on an unknown ROM ends this process, not the
// app; PictureClient sees it disconnect and the library goes on with the next ROM.
// SPDX-License-Identifier: GPL-2.0-or-later
package io.github.replaynes.android;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Message;
import android.os.Messenger;
import android.os.Process;
import android.os.RemoteException;
import android.util.Log;

public class PictureService extends Service {
    static final int MSG_MAKE = 1;
    static final int MSG_DONE = 2;  // arg1: 1 made, 0 no picture; arg2: this process's pid

    private static native boolean nativeMakeRomPicture(String rom, String out);

    private HandlerThread worker;
    private Messenger messenger;

    @Override
    public void onCreate() {
        super.onCreate();
        // The app's native code, as the app loads it (MainActivity.getLibraries).
        System.loadLibrary("SDL3");
        System.loadLibrary("main");
        worker = new HandlerThread("rom-picture", Process.THREAD_PRIORITY_BACKGROUND);
        worker.start();
        messenger = new Messenger(new Handler(worker.getLooper()) {
            @Override
            public void handleMessage(Message msg) {
                if (msg.what != MSG_MAKE) return;
                Bundle b = msg.getData();
                String rom = b.getString("rom"), out = b.getString("out");
                boolean made = rom != null && out != null && nativeMakeRomPicture(rom, out);
                Message reply = Message.obtain(null, MSG_DONE, made ? 1 : 0, Process.myPid());
                try {
                    if (msg.replyTo != null) msg.replyTo.send(reply);
                } catch (RemoteException e) {
                    Log.w("ReplayNES", "pictures: reply: " + e);
                }
            }
        });
    }

    @Override
    public IBinder onBind(Intent intent) {
        return messenger.getBinder();
    }

    @Override
    public void onDestroy() {
        if (worker != null) worker.quitSafely();
        super.onDestroy();
    }
}
