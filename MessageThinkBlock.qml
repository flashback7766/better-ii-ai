pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var messageData: {}
    property bool done: true
    property bool completed: false

    property real thinkBlockBackgroundRounding: Appearance.rounding.small
    property real thinkBlockHeaderPaddingVertical: 3
    property real thinkBlockHeaderPaddingHorizontal: 10
    property real thinkBlockComponentSpacing: 2

    // Detect if this think block contains command output
    readonly property bool isCommandOutput: {
        const s = (root.segmentContent ?? "").toString();
        return s.includes("[[ Output of") || s.includes("[[ Command exited");
    }
    readonly property bool commandFinished: {
        const s = (root.segmentContent ?? "").toString();
        return s.includes("[[ Command exited");
    }
    readonly property bool commandSucceeded: {
        const s = (root.segmentContent ?? "").toString();
        return s.includes("code 0 (");
    }

    // Use a safe threshold — don't reference messageTextBlock (forward ref, undefined on first eval)
    property var collapseAnimation: root.implicitHeight > 120 ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveFast
    property bool collapsed: root.completed // Auto-collapse when done

    // Animated dots (0-3) while thinking/running — updated by a Timer so they actually animate
    property int _dotCount: 0
    Timer {
        id: dotTimer
        interval: 500
        repeat: true
        running: !root.completed
        onTriggered: root._dotCount = (root._dotCount + 1) % 4
        onRunningChanged: if (!running) root._dotCount = 0
    }
    readonly property string _dots: "...".substring(0, root._dotCount)

    Layout.fillWidth: true
    implicitHeight: collapsed ? header.implicitHeight : columnLayout.implicitHeight
    // Only pay GPU compositing cost when expanded — collapsed is just the header
    layer.enabled: !collapsed
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: thinkBlockBackgroundRounding
        }
    }

    Behavior on implicitHeight {
        enabled: root.completed ?? false
        NumberAnimation {
            duration: collapseAnimation.duration
            easing.type: collapseAnimation.type
            easing.bezierCurve: collapseAnimation.bezierCurve
        }
    }

    ColumnLayout {
        id: columnLayout
        width: parent.width
        spacing: 0

        Rectangle { // Header background
            id: header
            color: Appearance.colors.colSurfaceContainerHighest
            Layout.fillWidth: true
            implicitHeight: thinkBlockTitleBarRowLayout.implicitHeight + thinkBlockHeaderPaddingVertical * 2

            MouseArea { // Click to reveal
                id: headerMouseArea
                enabled: root.completed
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    root.collapsed = !root.collapsed
                }
            }

            RowLayout { // Header content
                id: thinkBlockTitleBarRowLayout
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: thinkBlockHeaderPaddingHorizontal
                anchors.rightMargin: thinkBlockHeaderPaddingHorizontal
                spacing: 10

                MaterialSymbol {
                    Layout.fillWidth: false
                    Layout.topMargin: 7
                    Layout.bottomMargin: 7
                    Layout.leftMargin: 3
                    text: root.isCommandOutput
                        ? (root.commandFinished
                            ? (root.commandSucceeded ? "check_circle" : "error")
                            : "terminal")
                        : "linked_services"
                    color: root.isCommandOutput && root.commandFinished && !root.commandSucceeded
                        ? Appearance.m3colors.m3error
                        : Appearance.m3colors.m3onSecondaryContainer
                }
                StyledText {
                    id: thinkBlockLanguage
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignLeft
                    text: root.isCommandOutput
                        ? (root.commandFinished
                            ? (root.commandSucceeded ? Translation.tr("Command completed") : Translation.tr("Command failed"))
                            : (Translation.tr("Running command") + root._dots))
                        : (root.completed ? Translation.tr("Thought") : (Translation.tr("Thinking") + root._dots))
                }
                Item { Layout.fillWidth: true }
                RippleButton { // Expand button
                    id: expandButton
                    visible: root.completed
                    implicitWidth: 22
                    implicitHeight: 22
                    colBackground: headerMouseArea.containsMouse ? Appearance.colors.colLayer2Hover
                        : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: { root.collapsed = !root.collapsed }
                    
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "keyboard_arrow_down"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                        rotation: root.collapsed ? 0 : 180
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }

                }
                
            }

        }

        Item {
            id: content
            Layout.fillWidth: true
            implicitHeight: collapsed ? 0 : contentBackground.implicitHeight + thinkBlockComponentSpacing
            clip: true

            Behavior on implicitHeight {
                enabled: root.completed ?? false
                NumberAnimation {
                    duration: collapseAnimation.duration
                    easing.type: collapseAnimation.type
                    easing.bezierCurve: collapseAnimation.bezierCurve
                }
            }

            Rectangle {
                id: contentBackground
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                implicitHeight: messageTextBlock.implicitHeight
                color: Appearance.colors.colLayer2

                // Load data for the message at the correct scope
                property bool editing: root.editing
                property bool renderMarkdown: root.renderMarkdown
                property bool enableMouseSelection: root.enableMouseSelection
                property var messageData: root.messageData
                property bool done: root.done

                MessageTextBlock {
                    id: messageTextBlock
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    segmentContent: root.segmentContent
                }
            }
        }
    }
}
