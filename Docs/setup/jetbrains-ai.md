# Set up JetBrains AI in Pulse

Pulse shows your JetBrains AI Assistant quota — how much of it is used, and when it refills — as a ring. It reads what your JetBrains IDE already saved on this Mac, so there is nothing to paste and nothing is sent anywhere.

## What you need

A JetBrains IDE (IntelliJ IDEA, PyCharm, WebStorm, GoLand, Rider, Android Studio and the rest) with AI Assistant signed in and used at least once, so the IDE has saved a quota.

## Steps

1. Open your IDE and use AI Assistant once — ask it anything — so it checks your quota.
2. In Pulse: **Settings → JetBrains AI**. Turn on **Show in panel**.
3. Within a few seconds the ring appears. If you have several IDEs, Pulse reads the one that saved its quota most recently.

The figure is as current as the IDE last left it: the IDE updates it while it runs, so with every IDE closed Pulse shows the last quota any of them saw.

## If it doesn't work

| Pulse says | What to do |
|---|---|
| Nothing saved on this Mac yet. Open the service's app once, then retry. | No IDE has saved a quota yet. Open an IDE, use AI Assistant once, then refresh. |
| The app didn't save a quota Pulse can read on this Mac. | The IDE keeps its settings file but no longer writes the quota into it. IDEs from version 2026.3 on fetch the quota online and keep it in memory, so Pulse can't read it yet. Older IDEs are not affected. |
| No limits reported. | The IDE saved a quota without a size (a free or unlimited licence, for instance). There is nothing to draw a ring for. |
| Couldn't read the reply. | The IDE's file isn't in the shape Pulse knows; an IDE update may have changed it. |

## What Pulse reads

Pulse reads one file, `options/AIAssistantQuotaManager2.xml`, in your IDE's settings folder under `~/Library/Application Support/JetBrains` (or `~/Library/Application Support/Google` for Android Studio). It never writes to it, never asks the Keychain, and sends nothing over the network.
