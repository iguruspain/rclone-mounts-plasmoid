import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    // cfg_ aliases – values come exclusively from plasmoid.configuration (main.xml defaults)
    // NO hardcoded value/checked on controls – exactly like Dockio
    property alias cfg_rcPort:       rcPortSpin.value
    property alias cfg_mountBase:    mountBaseField.text
    property alias cfg_pollInterval: pollSpin.value
    property alias cfg_fetchOnStart: fetchOnStartCheck.checked
    property alias cfg_autoStartRcd: autoStartCheck.checked

    Kirigami.FormLayout {

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "RC Daemon"
        }

        QQC2.SpinBox {
            id: rcPortSpin
            Kirigami.FormData.label: "Port:"
            from: 1024
            to: 65535
            stepSize: 1
        }

        QQC2.CheckBox {
            id: autoStartCheck
            Kirigami.FormData.label: i18n("Autostart:")
            text: i18n("Start daemon automatically if not running")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Mount Points")
        }

        QQC2.TextField {
            id: mountBaseField
            Kirigami.FormData.label: i18n("Base folder:")
            placeholderText: i18n("$HOME/mnt/rclone")
            Layout.minimumWidth: 280
        }

        Kirigami.InlineMessage {
            Kirigami.FormData.label: " "
            Layout.fillWidth: true
            text: i18n("Each remote will be mounted as a subfolder (e.g. ~/mnt/rclone/gdrive)")
            visible: true
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Behavior")
        }

        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: i18n("Poll interval (s):")
            from: 5
            to: 300
            stepSize: 5
        }

        QQC2.CheckBox {
            id: fetchOnStartCheck
            Kirigami.FormData.label: i18n("Fetch on start:")
            text: i18n("Fetch mount states on startup")
        }
    }
}
