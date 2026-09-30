import QtQuick
import Quickshell.Io

// Bounded JSON subprocess reader. No dashboard/global-service dependencies.
Item {
    id: reader
    required property string providerId
    required property string scriptPath
    property var commandArguments: [providerId]
    property bool retainOnFailure: false
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
        process.command = ["bash", scriptPath].concat(commandArguments);
        process.running = true;
        deadline.restart();
    }

    Process {
        id: process
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => reader.buffer += chunk
        }
        onExited: code => {
            deadline.stop();
            try {
                if (code === 0 && !reader.timedOut && reader.buffer.length > 0) {
                    const parsed = JSON.parse(reader.buffer);
                    reader.result = parsed && !parsed.error ? parsed : null;
                } else if (!reader.retainOnFailure) {
                    reader.result = null;
                }
            } catch (error) {
                if (!reader.retainOnFailure)
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
            if (!reader.retainOnFailure)
                reader.result = null;
        }
    }
}
