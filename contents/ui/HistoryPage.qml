// HistoryPage.qml – tab with history of recently transferred files

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

ColumnLayout {
    id: page
    spacing: 0

    // Header: title + clear button
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: 0

        PlasmaComponents.Label {
            text: transferHistory.length > 0
                  ? transferHistory.length + " transferred files"
                  : ""
            font.pixelSize: 11
            opacity: 0.6
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            icon.name: "edit-clear-history"
            visible: transferHistory.length > 0
            display: PlasmaComponents.ToolButton.IconOnly
            onClicked: transferHistory = []
            PlasmaComponents.ToolTip { text: "Clear history" }
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            display: PlasmaComponents.ToolButton.IconOnly
            onClicked: checkTransfers()
            PlasmaComponents.ToolTip { text: "Refresh" }
        }
    }

    // Divider
    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#20808080"
    }

    // Transferred files list
    PlasmaComponents.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        background: null

        contentItem: ListView {
            id: histList
            clip: true
            highlight: PlasmaExtras.Highlight {}
            highlightMoveDuration: 0
            highlightResizeDuration: 0
            currentIndex: -1
            model: transferHistory

            delegate: PlasmaComponents.ItemDelegate {
                id: hDel
                width: histList.width
                height: Kirigami.Units.gridUnit * 3.2
                hoverEnabled: true

                property var    entry:    modelData
                property bool   hasError: entry.error && entry.error !== ""
                property string fileName: {
                    var n = entry.name || ""
                    // Show only the last part of the path
                    var slash = n.lastIndexOf("/")
                    return slash >= 0 ? n.substring(slash + 1) : n
                }
                property string filePath: {
                    var n = entry.name || ""
                    var slash = n.lastIndexOf("/")
                    return slash > 0 ? n.substring(0, slash) : ""
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    // Status icon (OK / error)
                    Kirigami.Icon {
                        source: hDel.hasError ? "dialog-error-symbolic"
                                              : "checkmark-symbolic"
                        width:  Kirigami.Units.iconSizes.small
                        height: Kirigami.Units.iconSizes.small
                        color:  hDel.hasError ? Kirigami.Theme.negativeTextColor
                                              : Kirigami.Theme.positiveTextColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // File name + path
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        PlasmaComponents.Label {
                            text: hDel.fileName || "(unknown file)"
                            font.bold: false
                            elide: Text.ElideLeft
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: {
                                var parts = []
                                if (hDel.filePath) parts.push(hDel.filePath)
                                if (hDel.hasError) parts.push("⚠ " + hDel.entry.error)
                                else parts.push(formatSize(hDel.entry.size || hDel.entry.bytes || 0))
                                return parts.join("  •  ")
                            }
                            font.pixelSize: Kirigami.Units.gridUnit * 0.75
                            opacity: 0.65
                            elide: Text.ElideLeft
                            Layout.fillWidth: true
                            color: hDel.hasError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        }
                    }

                    // Čas
                    PlasmaComponents.Label {
                        text: formatRelTime(hDel.entry.completedAt || hDel.entry.startedAt || "")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                        opacity: 0.5
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: "#25808080"
                }
            }

            // Empty state
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - (Kirigami.Units.largeSpacing * 4)
                visible: histList.count === 0
                icon.name: "view-history"
                text: "No transfer history"
                explanation: rcRunning
                             ? "History will appear after the first transfer completes"
                             : "Start the RC daemon to monitor transfers"
            }
        }
    }

    // Status bar at bottom
    PlasmaExtras.PlasmoidHeading {
        Layout.fillWidth: true
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                text: rcRunning ? "Daemon running on :" + rcPort : "Daemon not running"
                font.pixelSize: 11
                opacity: 0.7
                Layout.fillWidth: true
            }
            PlasmaComponents.BusyIndicator {
                visible: loading
                running: loading
                width: 18; height: 18
            }
        }
    }
}
