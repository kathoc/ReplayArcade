// The app's side of the picture process (PictureService; docs/plans/2026-11-22-library-pictures-robust.md): one ROM
// at a time, from the library's picture worker thread through MainActivity's startRomPicture / romPictureState /
// cancelRomPicture (JNI, main_android.cpp). The service process dying while it works is a crash of that ROM.
// SPDX-License-Identifier: GPL-2.0-or-later
package io.github.replaynes.android;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Message;
import android.os.Messenger;
import android.os.Process;
import android.os.RemoteException;
import android.util.Log;
import java.util.List;

final class PictureClient {
    static final int RUNNING = 0, MADE = 1, FAILED = 2, CRASHED = 3, UNAVAILABLE = 4;

    private final Context context;
    private final HandlerThread replies = new HandlerThread("rom-picture-replies");
    private final Messenger replyTo;
    private final Object lock = new Object();
    private Messenger service;          // bound (lock)
    private boolean bound;
    private int state = MADE;           // of the current request (lock)
    private boolean cancelling;

    PictureClient(Context context) {
        this.context = context.getApplicationContext();
        replies.start();
        replyTo = new Messenger(new Handler(replies.getLooper()) {
            @Override
            public void handleMessage(Message msg) {
                if (msg.what != PictureService.MSG_DONE) return;
                synchronized (lock) {
                    if (state == RUNNING) state = msg.arg1 == 1 ? MADE : FAILED;
                    lock.notifyAll();
                }
            }
        });
    }

    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            synchronized (lock) {
                service = new Messenger(binder);
                lock.notifyAll();
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            // The picture process died (a core crash, or killed by cancel / the OS): the request ends with it.
            synchronized (lock) {
                service = null;
                if (state == RUNNING) state = CRASHED;
                lock.notifyAll();
            }
            Log.w("ReplayNES", "pictures: the picture process ended");
        }
    };

    /** Sends one request; false when the service cannot be reached (the library then works in the app). */
    boolean start(String rom, String out) {
        synchronized (lock) {
            if (!bound) {
                bound = context.bindService(new Intent(context, PictureService.class), connection, Context.BIND_AUTO_CREATE);
                if (!bound) return false;
            }
            long until = System.currentTimeMillis() + 10_000;  // a new process starts (or restarts after a crash)
            while (service == null && System.currentTimeMillis() < until) {
                try {
                    lock.wait(until - System.currentTimeMillis());
                } catch (InterruptedException e) {
                    return false;
                }
            }
            if (service == null) return false;
            Message m = Message.obtain(null, PictureService.MSG_MAKE);
            Bundle b = new Bundle();
            b.putString("rom", rom);
            b.putString("out", out);
            m.setData(b);
            m.replyTo = replyTo;
            state = RUNNING;
            cancelling = false;
            try {
                service.send(m);
            } catch (RemoteException e) {
                state = CRASHED;
            }
            return true;
        }
    }

    int state() {
        synchronized (lock) {
            return state;
        }
    }

    /** Ends the picture process (a game opened, the app closing); the next request starts a new one. */
    void cancel() {
        int pid = picturePid();
        synchronized (lock) {
            cancelling = true;
        }
        if (pid > 0) Process.killProcess(pid);
    }

    private int picturePid() {
        ActivityManager am = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningAppProcessInfo> list = am != null ? am.getRunningAppProcesses() : null;
        if (list == null) return 0;
        String name = context.getPackageName() + ":pictures";
        for (ActivityManager.RunningAppProcessInfo p : list)
            if (name.equals(p.processName)) return p.pid;
        return 0;
    }
}
