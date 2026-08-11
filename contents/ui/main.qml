// Rclone Mounts Plasmoid – KDE Plasma 6 / Qt 6

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    switchWidth:  Kirigami.Units.gridUnit * 5
    switchHeight: Kirigami.Units.gridUnit * 5

    Plasmoid.status: rcRunning
                     ? PlasmaCore.Types.ActiveStatus
                     : PlasmaCore.Types.PassiveStatus

    toolTipMainText: i18n("Rclone Mounts")
    toolTipSubText: rcRunning
                    ? i18n("%1 / %2 mounted", Object.keys(activeMounts).length, remotes.length)
                    : i18n("RC daemon is not running")

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: rcRunning ? i18n("Stop RC Daemon") : i18n("Start RC Daemon")
            icon.name: rcRunning ? "media-playback-stop" : "media-playback-start"
            onTriggered: {
                if (rcRunning) {
                    exe.run("pkill -f 'rclone rcd.*" + rcPort + "' 2>&1 || true")
                    rcRunning = false
                    activeMounts = {}
                } else {
                    startDaemon()
                }
            }
        }
    ]

    // ── Configuration ──────────────────────────────────────────────────────────
    property string mountBase: {
        var base = plasmoid.configuration.mountBase !== ""
                   ? plasmoid.configuration.mountBase
                   : "$HOME/mnt/rclone"
        if (homeDir !== "") {
            base = base.replace(/\$HOME/g, homeDir).replace(/^~/, homeDir)
        }
        return base
    }
    property int    rcPort:       plasmoid.configuration.rcPort > 0
                                  ? plasmoid.configuration.rcPort : 5572
    property string rcAddr:       "localhost:" + rcPort
    property int    pollInterval: plasmoid.configuration.pollInterval > 0
                                  ? plasmoid.configuration.pollInterval : 10
    property bool   autoStartRcd: plasmoid.configuration.autoStartRcd

    // ── State ──────────────────────────────────────────────────────────────────
    property string homeDir:         ""
    property var    remotes:         []
    property var    activeMounts:    ({})
    property bool   rcRunning:       false
    property bool   loading:         true
    property string errorMsg:        ""
    property string filterText:      ""
    property var    remoteTypes:     ({})
    property var    transferHistory: []   // completed transfers
    property var    activeTransfers: []   // currently in progress
    property var    _activePctCache: ({}) // clamped pct per filename – never decreases
    property var    autoMountList:   []   // remotes with auto-mount on network startup

    // ── Helper functions ───────────────────────────────────────────────────────
    function formatSize(bytes) {
        if (!bytes || bytes < 0) return "?"
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB"
        return (bytes / 1073741824).toFixed(2) + " GB"
    }

    // Relative time in style "2 min ago"
    function formatRelTime(isoStr) {
        if (!isoStr) return ""
        try {
            var d   = new Date(isoStr)
            var now = new Date()
            var sec = Math.floor((now - d) / 1000)
            if (sec < 5)     return "just now"
            if (sec < 60)    return sec + "s ago"
            if (sec < 3600)  return Math.floor(sec / 60) + " min ago"
            if (sec < 86400) return Math.floor(sec / 3600) + " hr ago"
            return Math.floor(sec / 86400) + " d ago"
        } catch(e) { return "" }
    }

    // Completion time in HH:MM format (ignores Go zero date)
    function formatTime(isoStr) {
        if (!isoStr) return ""
        try {
            var d = new Date(isoStr)
            if (isNaN(d.getTime()) || d.getFullYear() < 2000) return ""
            return d.getHours().toString().padStart(2, "0") + ":"
                 + d.getMinutes().toString().padStart(2, "0")
        } catch(e) { return "" }
    }

    // Relative time – ignores zero date
    function safeRelTime(isoStr) {
        if (!isoStr) return ""
        try {
            var d = new Date(isoStr)
            if (isNaN(d.getTime()) || d.getFullYear() < 2000) return ""
            return formatRelTime(isoStr)
        } catch(e) { return "" }
    }

    // Extracts the best available timestamp from a transfer object
    // rclone uses snake_case: completed_at, started_at
    function bestTime(entry) {
        var candidates = [entry.completed_at, entry.completedAt,
                          entry.started_at,   entry.startedAt,
                          entry.timestamp]
        for (var i = 0; i < candidates.length; i++) {
            var t = candidates[i]
            if (t && formatTime(t) !== "") return t
        }
        return ""
    }

    // Transfer speed (2 decimal places)
    function formatSpeed(bps) {
        if (!bps || bps <= 0) return ""
        if (bps < 1024)       return bps.toFixed(2) + " B/s"
        if (bps < 1048576)    return (bps / 1024).toFixed(2) + " KB/s"
        if (bps < 1073741824) return (bps / 1048576).toFixed(2) + " MB/s"
        return (bps / 1073741824).toFixed(2) + " GB/s"
    }

    function remoteIcon(remote) {
        var t = remoteTypes[remote] || ""
        switch(t) {
            case "drive":     return "folder-gdrive"
            case "dropbox":   return "folder-dropbox"
            case "onedrive":  return "folder-onedrive"
            case "owncloud":  return "folder-owncloud"
            case "nextcloud": return "folder-owncloud"
            case "sftp":      return "folder-network"
            case "ftp":       return "folder-network"
            case "smb":       return "folder-network"
            case "nfs":       return "folder-network"
            case "webdav":    return "folder-network"
            case "http":      return "folder-network"
            case "local":     return "folder"
            case "s3":        return "folder-cloud"
            case "b2":        return "folder-cloud"
            case "box":       return "folder-cloud"
            case "mega":      return "folder-cloud"
            case "pcloud":    return "folder-cloud"
            default:          return "folder-cloud"
        }
    }

    // ── Commands ──────────────────────────────────────────────────────────────
    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) {
            handleOutput(src, data["exit code"], data["stdout"].trim(), data["stderr"].trim())
            disconnectSource(src)
        }
        function run(cmd) { connectSource(cmd) }
    }

    function handleOutput(cmd, code, out, err) {
        loading = false
        if (cmd.indexOf("echo $HOME") !== -1) {
            if (code === 0) homeDir = out
            fetchRemotes()
            loadAutoMounts()
            saveMountConfig()
            return
        }
        if (cmd.indexOf("automount.conf") !== -1 && cmd.indexOf("echo") === -1) {
            autoMountList = (code === 0 && out !== "")
                ? out.split("\n").map(function(l){ return l.trim() }).filter(function(l){ return l.length > 0 })
                : []
            return
        }
        if (cmd.indexOf("listremotes") !== -1) {
            if (code === 0 && out !== "") {
                var lines = out.split("\n").filter(function(l){ return l.trim() !== "" })
                var names = []
                var types = {}
                lines.forEach(function(line) {
                    var parts = line.trim().split(/\s+/)
                    var name = parts[0]
                    var type = parts[1] || ""
                    names.push(name)
                    types[name] = type
                })
                remotes = names
                remoteTypes = types
            } else {
                remotes = []
                remoteTypes = {}
                errorMsg = cleanError(err)
            }
            return
        }
        if (cmd.indexOf("mount/listmounts") !== -1) {
            if (code === 0) {
                rcRunning = true
                errorMsg = ""
                try {
                    var p = JSON.parse(out)
                    var nm = {}
                    if (p.mountPoints) {
                        p.mountPoints.forEach(function(m){ nm[m.Fs] = m.MountPoint })
                    }
                    activeMounts = nm
                } catch(e) {
                    activeMounts = {}
                }
            } else {
                rcRunning = false
                activeMounts = {}
                errorMsg = "RC daemon is not running on port " + rcPort + "."
            }
            return
        }
        if (cmd.indexOf("mount/mount") !== -1 || cmd.indexOf("mount/unmount") !== -1) {
            if (code === 0) {
                // success – clear any previous error and then verify daemon state
                errorMsg = ""
                Qt.callLater(checkDaemon)
            } else {
                // failure – rclone rc sends errors to stdout as JSON, so check both
                var rawErr = err !== "" ? err : out
                errorMsg = cleanError(rawErr)
            }
            return
        }
        if (cmd.indexOf("core/stats") !== -1 && cmd.indexOf("core/transferred") === -1) {
            if (code === 0) {
                try {
                    var sp = JSON.parse(out)
                    // Show all active transfers (including bytes=0 at upload start)
                    // exclude only 100% completed (before they move to core/transferred)
                    var raw = sp.transferring
                        ? sp.transferring.filter(function(t) {
                            return (t.percentage || 0) < 100
                          })
                        : []
                    // Clear cache for files that are no longer in progress
                    var activeNames = {}
                    raw.forEach(function(t) { if (t.name) activeNames[t.name] = true })
                    var newCache = {}
                    Object.keys(_activePctCache).forEach(function(k) {
                        if (activeNames[k]) newCache[k] = _activePctCache[k]
                    })
                    // Aggregate: file.txt + file.txt.part → one record under "file.txt"
                    var byDisplayName = {}
                    raw.forEach(function(t) {
                        var rawName = t.name || ""
                        var displayName = rawName.replace(/\.part$/, "")
                        var p = t.percentage || 0
                        var sz = t.size || 0
                        var by = t.bytes || 0
                        if (!p && sz > 0 && by > 0) p = Math.min(99, by / sz * 100)
                        // Clamp: pct never decreases
                        var cacheKey = displayName
                        var prev = newCache[cacheKey] || 0
                        p = Math.max(prev, p)
                        if (p < 99) newCache[cacheKey] = p
                        var existing = byDisplayName[displayName]
                        if (!existing) {
                            var clone = Object.assign({}, t)
                            clone._displayName = displayName
                            clone._pct = p
                            byDisplayName[displayName] = clone
                        } else {
                            // Merge: take larger bytes, larger pct, prefer non-.part record
                            if ((t.bytes || 0) > (existing.bytes || 0)) existing.bytes = t.bytes
                            if (p > existing._pct) existing._pct = p
                            // If existing was .part and new one isn't → prefer non-.part metadata
                            if (rawName === displayName) {
                                existing.size    = t.size
                                existing.speed   = t.speed
                                existing.eta     = t.eta
                                existing.srcFs   = t.srcFs
                                existing.dstFs   = t.dstFs
                            }
                        }
                    })
                    activeTransfers = Object.keys(byDisplayName).map(function(k){ return byDisplayName[k] })
                    _activePctCache = newCache
                } catch(e) { activeTransfers = [] }
            } else {
                activeTransfers = []
            }
            return
        }
        if (cmd.indexOf("core/transferred") !== -1) {
            if (code === 0) {
                try {
                    var tp = JSON.parse(out)
                    if (tp.transferred && tp.transferred.length > 0) {
                        // Deduplicate: one record per file, accumulate bytes from chunks
                        var byName = {}
                        tp.transferred.forEach(function(t) {
                            if (t.checked && !(t.error && t.error !== "")) return  // skip verification without error
                            var name = t.name || ""
                            // Skip temp files (qt_temp.*, .tmp, ~*, etc.) if no error
                            var baseName = name.substring(name.lastIndexOf("/") + 1)
                            var isTmp = /^qt_temp\.|^\..*[a-zA-Z0-9]{5,}$|^\.~lock\.|^~|\.part$/.test(baseName)
                            if (isTmp && !(t.error && t.error !== "")) return
                            var prev = byName[name]
                            if (!prev) {
                                byName[name] = Object.assign({}, t)
                            } else {
                                // Merge chunks: accumulate bytes, propagate error, keep newest timestamp
                                var merged = Object.assign({}, prev)
                                merged.bytes = (prev.bytes || 0) + (t.bytes || 0)
                                merged.size  = t.size || prev.size
                                if (t.error && t.error !== "") merged.error = t.error
                                var tNew = new Date(t.completed_at    || t.started_at    || "")
                                var tOld = new Date(prev.completed_at || prev.started_at || "")
                                if (!isNaN(tNew) && tNew > tOld) {
                                    merged.completed_at = t.completed_at
                                    merged.started_at   = t.started_at
                                }
                                byName[name] = merged
                            }
                        })
                        // Sort descending (newest first)
                        var deduped = Object.keys(byName).map(function(k){ return byName[k] })
                        deduped.sort(function(a, b) {
                            var ta = new Date(a.completed_at || a.started_at || "")
                            var tb = new Date(b.completed_at || b.started_at || "")
                            return tb - ta
                        })
                        transferHistory = deduped.slice(0, 100)
                    }
                } catch(e) {}
            }
            return
        }
        if (cmd.indexOf("rcd") !== -1) {
            daemonStartTimer.start()
        }
    }

    function fetchRemotes()   { loading = true; exe.run("rclone listremotes --long") }
    function checkDaemon()    { exe.run("rclone rc mount/listmounts --rc-addr=" + rcAddr + " 2>&1") }

    // ── Auto-mount ────────────────────────────────────────────────────────────
    property string _amConf: homeDir !== "" ? homeDir + "/.config/rclone-plasmoid/automount.conf" : ""

    function loadAutoMounts() {
        if (homeDir === "") return
        exe.run("cat '" + homeDir + "/.config/rclone-plasmoid/automount.conf' 2>/dev/null || true")
    }

    // Writes current mountBase to shared config file for automount script
    function saveMountConfig() {
        if (homeDir === "" || mountBase === "") return
        var confDir = homeDir + "/.config/rclone-plasmoid"
        exe.run("mkdir -p '" + confDir + "' && printf 'mountBase=%s\\n' '" + mountBase + "' > '" + confDir + "/config'")
    }
    onMountBaseChanged: saveMountConfig()

    function toggleAutoMount(remote) {
        if (homeDir === "") return
        var conf = homeDir + "/.config/rclone-plasmoid/automount.conf"
        var idx = autoMountList.indexOf(remote)
        if (idx >= 0) {
            exe.run("grep -vxF '" + remote + "' '" + conf + "' > /tmp/.rclone-am-tmp && mv /tmp/.rclone-am-tmp '" + conf + "'")
            var removed = autoMountList.slice()
            removed.splice(idx, 1)
            autoMountList = removed
        } else {
            exe.run("mkdir -p '" + homeDir + "/.config/rclone-plasmoid' && echo '" + remote + "' >> '" + conf + "'")
            autoMountList = autoMountList.concat([remote])
        }
    }
    function checkTransfers() { if (rcRunning) exe.run("rclone rc core/transferred --rc-addr=" + rcAddr + " 2>&1") }
    function checkStats()     { if (rcRunning) exe.run("rclone rc core/stats --rc-addr=" + rcAddr + " 2>&1") }
    function startDaemon()    { errorMsg = "Starting..."; exe.run("rclone rcd --rc-addr=" + rcAddr + " --rc-no-auth &") }
    function openFolder(path) { exe.run("xdg-open '" + path + "'") }

    // Extracts readable part of error – removes JSON block "Details: [...]" from rclone/Google API
    function cleanError(errStr) {
        if (!errStr) return ""
        var clean = errStr
        // Try to extract message from rclone rc JSON error: {"error":"..."} or {"core":{"error":"..."}}
        try {
            var j = JSON.parse(clean)
            if (j.error) return j.error
            if (j.core && j.core.error) return j.core.error
            if (j.message) return j.message
        } catch(e) {}
        // Remove "Details:" block (with or without preceding \n)
        var di = clean.indexOf("Details:")
        if (di > 0) clean = clean.substring(0, di).trim()
        // Remove JSON blocks (everything from first "{")
        var ji = clean.indexOf("{")
        if (ji > 0) clean = clean.substring(0, ji).trim()
        // Take only the first non-empty line
        var lines = clean.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (l.length > 0) {
                return l.length > 80 ? l.substring(0, 77) + "…" : l
            }
        }
        return clean.trim()
    }

    // Tries to re-upload failed files by triggering VFS refresh on all active mounts
    function retryFailed() {
        var mounts = Object.keys(activeMounts)
        mounts.forEach(function(fs) {
            exe.run("rclone rc vfs/refresh dir=/ recursive=true fs=" + fs + " --rc-addr=" + rcAddr + " 2>&1")
        })
        Qt.callLater(checkTransfers)
    }

    function doMount(remote) {
        var path = mountBase + "/" + remote.replace(/:$/, "")
        var cacheBase = (homeDir !== "" ? homeDir : "$HOME") + "/.cache/rclone-mounts"
        var cacheDir = cacheBase + "/" + remote.replace(/:$/, "")
        errorMsg = ""
        var json = '{"fs":"' + remote + '","mountPoint":"' + path + '",'
            + '"mountOpt":{"vfs-cache-mode":"writes","vfs-write-back":"1s",'
            + '"attr-timeout":"1s","dir-cache-time":"5s","cache-dir":"' + cacheDir + '"}}'
        exe.run("mkdir -p '" + path + "' '" + cacheDir + "' && rclone rc mount/mount --json '" + json
            + "' --rc-addr=" + rcAddr)
    }
    function doUnmount(mp) {
        errorMsg = ""
        exe.run("rclone rc mount/unmount mountPoint='" + mp + "' --rc-addr=" + rcAddr)
    }

    // Slow timer: check mounts + completed transfers
    Timer {
        interval: pollInterval * 1000
        running: true; repeat: true
        onTriggered: { checkDaemon(); checkTransfers() }
    }
    // Fast timer: active transfers (every 2s)
    Timer {
        interval: 2000
        running: rcRunning; repeat: true
        onTriggered: checkStats()
    }
    Timer { id: daemonStartTimer; interval: 2500; onTriggered: checkDaemon() }
    Component.onCompleted: {
        exe.run("echo $HOME")
        if (plasmoid.configuration.fetchOnStart) checkDaemon()
    }
    onRcRunningChanged: {
        if (!rcRunning && autoStartRcd) startDaemon()
    }

    // ════════════════════════════════════════════════════════════════════════
    //  COMPACT VIEW
    // ════════════════════════════════════════════════════════════════════════
    compactRepresentation: MouseArea {
        id: compactRoot
        property bool wasExpanded: false
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onPressed:  wasExpanded = root.expanded
        onClicked:  root.expanded = !wasExpanded

        Kirigami.Icon {
            anchors.fill: parent
            active: compactRoot.containsMouse
            source: "folder-cloud"
        }

        Rectangle {
            visible: Object.keys(activeMounts).length > 0
            anchors { right: parent.right; bottom: parent.bottom; margins: 2 }
            width: 8; height: 8; radius: 4
            color: Kirigami.Theme.positiveTextColor
            border.color: Kirigami.Theme.backgroundColor
            border.width: 1
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  FULL VIEW
    // ════════════════════════════════════════════════════════════════════════
    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth:  Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 24
        Layout.maximumWidth:  Kirigami.Units.gridUnit * 34
        Layout.maximumHeight: Kirigami.Units.gridUnit * 40
        collapseMarginsHint: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Global error banner – shows any command failure or daemon down
            Kirigami.InlineMessage {
                id: globalErrorBanner
                Layout.fillWidth: true
                Layout.minimumHeight: visible ? implicitHeight : 0
                Layout.maximumHeight: visible ? implicitHeight : 0
                Layout.margins: Kirigami.Units.smallSpacing
                type: Kirigami.MessageType.Error
                visible: errorMsg !== ""
                text: cleanError(errorMsg)
            }

            // StackView remains as in the functional version – tab bar is inside MainPage
            QQC2.StackView {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: MainPage {}
            }
        }
    }
}
