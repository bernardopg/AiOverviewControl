import QtQuick
import Quickshell.Io

// Bounded JSON subprocess reader. No dashboard/global-service dependencies.
Item {
    id: reader
    required property string providerId
    required property string scriptPath
    property int timeoutMs: 45000
    property var result: null
    readonly property bool running: process.running
    property string buffer: ""
    property bool timedOut: false
    signal completed()
    visible: false

    function refresh() {
        if (process.running)
            return;
        buffer = "";
        timedOut = false;
        process.running = true;
        deadline.restart();
    }

    Process {
        id: process
        command: ["bash", reader.scriptPath, reader.providerId]
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => reader.buffer += chunk
        }
        onExited: code => {
            deadline.stop();
            try {
                const parsed = code === 0 && !reader.timedOut ? JSON.parse(reader.buffer) : null;
                reader.result = parsed && !parsed.error ? parsed : null;
            } catch (error) {
                reader.result = null;
            }
            reader.buffer = "";
            reader.completed();
        }
    }
    Timer {
        id: deadline
        interval: reader.timeoutMs
        onTriggered: {
            reader.timedOut = true;
            process.running = false;
            reader.buffer = "";
            reader.result = null;
        }
    }
}
