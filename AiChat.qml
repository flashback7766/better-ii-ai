import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        // Escape closes any open popup
        if (event.key === Qt.Key_Escape) {
            if (modelPickerPopup.isOpen) { modelPickerPopup.close(); event.accepted = true; return; }
            if (functionsPopup.isOpen) { functionsPopup.close(); event.accepted = true; return; }
        }
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.newChat();
        }
        // Ctrl+1..9 to switch models
        if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier)) {
            const num = event.key - Qt.Key_1;
            if (num >= 0 && num < 9 && num < Ai.modelList.length) {
                Ai.setModel(Ai.modelList[num]);
                event.accepted = true;
            }
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file. Only works with Gemini."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "new",
            description: Translation.tr("Start new chat (saves current to history buffer)"),
            execute: () => {
                Ai.newChat();
            }
        },
        {
            name: "stop",
            description: Translation.tr("Stop all running AI processes"),
            execute: () => {
                Ai.abortAll();
                Ai.addMessage(Translation.tr("All AI processes stopped"), Ai.interfaceRole);
            }
        },
        {
            name: "addlocal",
            description: Translation.tr("Add a local model. Usage: /addlocal MODEL [ENDPOINT]\nDefaults: Ollama (localhost:11434). For LM Studio use /addlocal MODEL http://localhost:1234/v1/chat/completions"),
            execute: args => {
                if (args.length === 0) {
                    Ai.addMessage(Translation.tr("**Usage:** `/addlocal MODEL_NAME [ENDPOINT]`\n\n**Examples:**\n- `/addlocal llama3.3` — Ollama (default)\n- `/addlocal deepseek-r1:32b` — Ollama with tag\n- `/addlocal my-model http://localhost:1234/v1/chat/completions` — LM Studio\n- `/addlocal model http://192.168.1.10:8000/v1/chat/completions` — Remote vLLM"), Ai.interfaceRole);
                    return;
                }
                const modelName = args[0];
                const endpoint = args.length > 1 ? args[1] : "";
                Ai.addLocalModel(modelName, endpoint, modelName);
            }
        },
        {
            name: "export",
            description: Translation.tr("Export chat to markdown file in Downloads"),
            execute: () => {
                Ai.exportChat();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        messageListView.positionViewAtEnd();
    }

    // Click-away overlay to close popups when clicking outside
    Rectangle {
        id: popupDismissOverlay
        parent: root
        anchors.fill: parent
        visible: modelPickerPopup.isOpen || functionsPopup.isOpen
        color: "transparent"
        z: 999
        MouseArea {
            anchors.fill: parent
            onClicked: {
                modelPickerPopup.close();
                functionsPopup.close();
            }
        }
    }

    // Model picker popup — lives at root level to escape inputWrapper's clip:true
    Rectangle {
        id: modelPickerPopup
        parent: root
        visible: opacity > 0
        enabled: opacity > 0
        z: 1000

        // Custom models first, then built-ins
        property var sortedModelList: {
            const custom  = Ai.modelList.filter(id =>  Ai.isRemovableModel(id));
            const builtin = Ai.modelList.filter(id => !Ai.isRemovableModel(id));
            return [...custom, ...builtin];
        }
        property bool hasCustomModels: sortedModelList.some(id => Ai.isRemovableModel(id))

        property bool isOpen: false

        function open() {
            functionsPopup.close();
            var pos = modelPickerButton.mapToItem(root, 0, 0);
            x = pos.x;
            y = pos.y - implicitHeight - 6;
            isOpen = true;
        }
        function close() {
            isOpen = false;
        }
        function toggle() {
            if (isOpen) close(); else open();
        }

        // Opacity animation
        opacity: isOpen ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // Scale animation from bottom-left (button origin)
        transform: Scale {
            id: popupScale
            origin.x: 0
            origin.y: modelPickerPopup.height
            xScale: modelPickerPopup.isOpen ? 1 : 0.92
            yScale: modelPickerPopup.isOpen ? 1 : 0.92
            Behavior on xScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on yScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        width: 280
        readonly property real maxPopupHeight: 400
        readonly property real naturalHeight: modelPickerColumn.implicitHeight + 12
        implicitHeight: Math.min(naturalHeight, maxPopupHeight)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        // Close when clicking outside
        Connections {
            target: messageInputField
            function onActiveFocusChanged() {
                if (messageInputField.activeFocus && modelPickerPopup.isOpen)
                    modelPickerPopup.close();
            }
        }

        Flickable {
            id: modelPickerFlickable
            anchors.fill: parent
            anchors.margins: 6
            contentHeight: modelPickerColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            // Smooth deceleration for touch/flick
            flickDeceleration: 1500
            maximumFlickVelocity: 1500

            // Smooth scroll animation for wheel input
            Behavior on contentY {
                id: scrollBehavior
                enabled: false
                SmoothedAnimation {
                    duration: 200
                    velocity: -1
                }
            }

            // Scroll bar
            Rectangle {
                id: modelPickerScrollbar
                parent: modelPickerFlickable
                visible: modelPickerFlickable.contentHeight > modelPickerFlickable.height
                anchors.right: parent.right
                anchors.rightMargin: -2
                width: 3
                radius: 1.5
                color: Appearance.colors.colSubtext
                opacity: modelPickerFlickable.moving ? 0.5 : 0.15
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                y: modelPickerFlickable.contentY / modelPickerFlickable.contentHeight * modelPickerFlickable.height
                height: Math.max(20, modelPickerFlickable.height / modelPickerFlickable.contentHeight * modelPickerFlickable.height)
                z: 10
            }

            // Mouse wheel support with smooth scrolling
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                onWheel: (wheel) => {
                    scrollBehavior.enabled = true;
                    const step = wheel.angleDelta.y * 0.8;
                    modelPickerFlickable.contentY = Math.max(0,
                        Math.min(modelPickerFlickable.contentHeight - modelPickerFlickable.height,
                            modelPickerFlickable.contentY - step));
                    wheel.accepted = true;
                    scrollResetTimer.restart();
                }
                Timer {
                    id: scrollResetTimer
                    interval: 300
                    onTriggered: scrollBehavior.enabled = false
                }
                onClicked: (mouse) => mouse.accepted = false
                onPressed: (mouse) => mouse.accepted = false
                onReleased: (mouse) => mouse.accepted = false
            }

            ColumnLayout {
                id: modelPickerColumn
                width: modelPickerFlickable.width
                spacing: 2

                StyledText {
                    Layout.leftMargin: 8
                    Layout.topMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Select model")
                }

                // Custom models section (only shown when custom models exist)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    visible: modelPickerPopup.hasCustomModels

                    StyledText {
                        Layout.leftMargin: 8
                        Layout.topMargin: 2
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                        text: Translation.tr("Custom")
                    }

                    Repeater {
                        model: modelPickerPopup.sortedModelList.filter(id => Ai.isRemovableModel(id))
                        delegate: RippleButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: _row.implicitHeight + 8
                            buttonRadius: Appearance.rounding.small
                            toggled: Ai.currentModelId === modelData
                            colBackground: toggled ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: { Ai.setModel(modelData, false); modelPickerPopup.close(); }
                            contentItem: RowLayout {
                                id: _row
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                spacing: 8
                                CustomIcon {
                                    visible: Ai.models[modelData]?.icon?.length > 0
                                    width: Appearance.font.pixelSize.normal; height: width
                                    source: Ai.models[modelData]?.icon ?? ""; colorize: true
                                    color: Appearance.m3colors.m3onSurface
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    StyledText { Layout.fillWidth: true; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onSurface; text: Ai.models[modelData]?.name ?? modelData; elide: Text.ElideRight }
                                    StyledText { Layout.fillWidth: true; visible: text.length > 0; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext; text: (Ai.models[modelData]?.description ?? "").split("\n")[0] ?? ""; elide: Text.ElideRight }
                                }
                                MaterialSymbol {
                                    text: "close"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Ai.removeModel(modelData) }
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.5
                    }
                }

                // Built-in models section label (only when custom models exist)
                StyledText {
                    visible: modelPickerPopup.hasCustomModels
                    Layout.leftMargin: 8
                    Layout.topMargin: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.6
                    text: Translation.tr("Built-in")
                }

                Repeater {
                    model: modelPickerPopup.sortedModelList.filter(id => !Ai.isRemovableModel(id))
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: _row2.implicitHeight + 8
                        buttonRadius: Appearance.rounding.small
                        toggled: Ai.currentModelId === modelData
                        colBackground: toggled ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { Ai.setModel(modelData, false); modelPickerPopup.close(); }
                        contentItem: RowLayout {
                            id: _row2
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 8
                            CustomIcon {
                                visible: Ai.models[modelData]?.icon?.length > 0
                                width: Appearance.font.pixelSize.normal; height: width
                                source: Ai.models[modelData]?.icon ?? ""; colorize: true
                                color: Appearance.m3colors.m3onSurface
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                StyledText { Layout.fillWidth: true; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.m3colors.m3onSurface; text: Ai.models[modelData]?.name ?? modelData; elide: Text.ElideRight }
                                StyledText { Layout.fillWidth: true; visible: text.length > 0; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext; text: (Ai.models[modelData]?.description ?? "").split("\n")[0] ?? ""; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }
        }
    }



    // Functions & Thinking popup
    Rectangle {
        id: functionsPopup
        parent: root
        visible: opacity > 0
        enabled: opacity > 0
        z: 1000

        property bool isOpen: false

        function open() {
            modelPickerPopup.close();
            var pos = functionsButton.mapToItem(root, 0, 0);
            x = pos.x;
            y = pos.y - implicitHeight - 6;
            // Clamp to not go off-screen left
            if (x + width > root.width) x = root.width - width - 6;
            isOpen = true;
        }
        function close() {
            isOpen = false;
        }
        function toggle() {
            if (isOpen) close(); else open();
        }

        opacity: isOpen ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        transform: Scale {
            origin.x: 0
            origin.y: functionsPopup.height
            xScale: functionsPopup.isOpen ? 1 : 0.92
            yScale: functionsPopup.isOpen ? 1 : 0.92
            Behavior on xScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on yScale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        width: 280
        implicitHeight: functionsPopupColumn.implicitHeight + 16
        clip: true
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        // Close when clicking outside
        Connections {
            target: messageInputField
            function onActiveFocusChanged() {
                if (messageInputField.activeFocus && functionsPopup.isOpen)
                    functionsPopup.close();
            }
        }

        ColumnLayout {
            id: functionsPopupColumn
            anchors.fill: parent
            anchors.margins: 6
            spacing: 6

            // --- Tools section ---
            StyledText {
                Layout.leftMargin: 8
                Layout.topMargin: 2
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Tools")
            }

            Repeater {
                model: Ai.availableTools
                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: _toolRow.implicitHeight + 8
                    buttonRadius: Appearance.rounding.small
                    toggled: Ai.currentTool === modelData
                    colBackground: toggled ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        Ai.setTool(modelData);
                        functionsPopup.close();
                    }
                    contentItem: RowLayout {
                        id: _toolRow
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8
                        MaterialSymbol {
                            text: modelData === "functions" ? "build" : modelData === "search" ? "search" : "block"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSurface
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: (Ai.toolDescriptions[modelData] ?? "").split("\n")[0] ?? ""
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // --- Divider ---
            Rectangle {
                visible: Ai.currentThinkingStyle !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.5
            }

            // --- Thinking Section ---
            ColumnLayout {
                visible: Ai.currentThinkingStyle !== ""
                Layout.fillWidth: true
                spacing: 6

                // Anthropic Style (Toggle)
                RowLayout {
                    visible: Ai.currentThinkingStyle === "anthropic"
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                            text: Translation.tr("Extended thinking")
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Think longer for complex tasks")
                        }
                    }

                    // Toggle component (Manual)
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: (Ai.thinkingEnabled && Ai.thinkingLevel > 0) ? Appearance.m3colors.m3primary : Appearance.colors.colLayer1
                        border.width: 1
                        border.color: (Ai.thinkingEnabled && Ai.thinkingLevel > 0) ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                        Rectangle {
                            width: 18; height: 18; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: (Ai.thinkingEnabled && Ai.thinkingLevel > 0) ? parent.width - width - 3 : 3
                            color: (Ai.thinkingEnabled && Ai.thinkingLevel > 0) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                            Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Ai.thinkingEnabled && Ai.thinkingLevel > 0) {
                                    Ai.thinkingEnabled = false; Ai.thinkingLevel = 0;
                                } else {
                                    Ai.thinkingEnabled = true; Ai.thinkingLevel = 2;
                                }
                                Persistent.states.ai.thinkingEnabled = Ai.thinkingEnabled;
                                Persistent.states.ai.thinkingLevel = Ai.thinkingLevel;
                            }
                        }
                    }
                }

                // Gemini Style (Levels)
                ColumnLayout {
                    visible: Ai.currentThinkingStyle === "gemini"
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.leftMargin: 8
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Thinking Level")
                    }
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4; spacing: 3
                        Repeater {
                            model: [{label:"Off",l:0},{label:"Low",l:1},{label:"Med",l:2},{label:"High",l:3}]
                            delegate: RippleButton {
                                Layout.fillWidth: true; implicitHeight: 28
                                buttonRadius: Appearance.rounding.small
                                property bool isActive: Ai.thinkingLevel === modelData.l
                                colBackground: isActive ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2
                                colBackgroundHover: isActive ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2Hover
                                onClicked: {
                                    Ai.thinkingLevel = modelData.l; Ai.thinkingEnabled = modelData.l > 0;
                                    Persistent.states.ai.thinkingEnabled = Ai.thinkingEnabled;
                                    Persistent.states.ai.thinkingLevel = Ai.thinkingLevel;
                                }
                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    font.pixelSize: 10
                                    color: parent.isActive ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                                    text: modelData.label
                                }
                            }
                        }
                    }
                    StyledText {
                        Layout.leftMargin: 8; Layout.bottomMargin: 2
                        font.pixelSize: 10; color: Appearance.colors.colSubtext; opacity: 0.7
                        text: [Translation.tr("Off"), Translation.tr("Low"), Translation.tr("Medium"), Translation.tr("High")][Ai.thinkingLevel]
                    }
                }
            }

            // --- Global Settings Section ---
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8
                Layout.topMargin: 4; Layout.bottomMargin: 4
                implicitHeight: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.5
            }

            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 12; Layout.bottomMargin: 12
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        text: Translation.tr("Auto-confirm")
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Run shell commands automatically")
                    }
                }

                // Global Settings Toggle (Matching Design)
                Rectangle {
                    width: 44; height: 24; radius: 12
                    color: Ai.functionsAutoConfirm ? Appearance.m3colors.m3primary : Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Ai.functionsAutoConfirm ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: Ai.functionsAutoConfirm ? parent.width - width - 3 : 3
                        color: Ai.functionsAutoConfirm ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
                        Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ai.functionsAutoConfirm = !Ai.functionsAutoConfirm;
                            Persistent.states.ai.functionsAutoConfirm = Ai.functionsAutoConfirm;
                        }
                    }
                }
            }
        }
    }


    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: 10

                    StatusItem {
                        icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                        statusText: ""
                        description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
                    }
                    StatusSeparator {}
                    StatusItem {
                        icon: "device_thermostat"
                        statusText: Ai.temperature.toFixed(1)
                        description: Translation.tr("Temperature\nChange with /temp VALUE")
                    }
                    StatusSeparator {
                        visible: Ai.tokenCount.total > 0
                    }
                    StatusItem {
                        visible: Ai.tokenCount.total > 0
                        icon: "token"
                        statusText: Ai.tokenCount.total
                        description: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                    }
                    StatusSeparator {
                        visible: Ai.generationSpeed > 0
                    }
                    StatusItem {
                        visible: Ai.generationSpeed > 0
                        icon: "speed"
                        statusText: Ai.generationSpeed.toFixed(1)
                        description: Translation.tr("Generation speed (tokens/sec)")
                    }
                    StatusItem {
                        visible: Ai.sessionCost > 0.0001
                        icon: "payments"
                        statusText: "$" + Ai.sessionCost.toFixed(4)
                        description: Translation.tr("Estimated session cost")
                    }
                    StatusSeparator {
                        visible: Ai.sessionSummary.length > 0
                    }
                    StatusItem {
                        visible: Ai.sessionSummary.length > 0
                        icon: "history_edu"
                        statusText: Translation.tr("Condensed")
                        description: Translation.tr("History has been semantically condensed to save space.\n\nSummary:\n%1").arg(Ai.sessionSummary)
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 10
                popin: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2

                // Pre-render off-screen items for smoother scrolling
                cacheBuffer: 600
                reuseItems: true

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                // Only auto-scroll if user is near the bottom (within 150px)
                property bool isNearBottom: (contentHeight - contentY - height) < 150
                onContentHeightChanged: {
                    if (isNearBottom)
                        Qt.callLater(positionViewAtEnd);
                }
                onCountChanged: {
                    // Auto-scroll when new messages are added
                    Qt.callLater(positionViewAtEnd);
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData];
                    }
                    messageInputField: root.inputField
                }
            }

            PagePlaceholder {
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "neurology"
                title: Translation.tr("Large language models")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand sidebar\nCtrl+P to pin sidebar\nCtrl+D to detach sidebar")
                shape: MaterialShape.Shape.PixelCircle
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: RowLayout {
                        spacing: 2
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.displayName ?? modelData.name
                        }
                        // Show × button for removable (custom/local) models
                        Rectangle {
                            visible: modelData.removable ?? false
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: commandButton.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "×"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.modelId) {
                                        Ai.removeModel(modelData.modelId);
                                        messageInputField.text = "";
                                    }
                                }
                            }
                        }
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 5
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 5
                }
                spacing: 0

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`,
                                        removable: Ai.isRemovableModel(model.target),
                                        modelId: model.target,
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr(`Load chat from %1`).arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                        }

                        function accept() {
                            root.handleInput(text);
                            text = "";
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste
                                    messageInputField.text += Quickshell.clipboardText;
                                    event.accepted = true;
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc: abort generation if running, otherwise detach file
                                if (Ai.isGenerating) {
                                    Ai.abortAll();
                                    event.accepted = true;
                                } else if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Period) {
                                // Ctrl+Shift+. to force stop everything
                                Ai.abortAll();
                                event.accepted = true;
                            }
                        }
                    }
                }
                RippleButton { // Send button / Stop button
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: messageInputField.text.length > 0 || Ai.isGenerating
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (Ai.isGenerating) {
                                Ai.abortAll();
                            } else {
                                const inputText = messageInputField.text;
                                root.handleInput(inputText);
                                messageInputField.clear();
                            }
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: Ai.isGenerating ? "stop" : "arrow_upward"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true
                    },
                    {
                        name: "new",
                        sendDirectly: true
                    },
                ]

                RippleButton {
                    // Model picker button
                    id: modelPickerButton
                    implicitWidth: modelPickerRow.implicitWidth + 12
                    implicitHeight: modelPickerRow.implicitHeight + 8
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    onClicked: modelPickerPopup.toggle()

                    contentItem: RowLayout {
                        id: modelPickerRow
                        anchors.centerIn: parent
                        spacing: 4
                        CustomIcon {
                            visible: Ai.models[Ai.currentModelId]?.icon?.length > 0
                            width: Appearance.font.pixelSize.small
                            height: Appearance.font.pixelSize.small
                            source: Ai.models[Ai.currentModelId]?.icon ?? ""
                            colorize: true
                            color: Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3onSurface
                            text: Ai.getModel()?.name ?? ""
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            text: "expand_more"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                RippleButton {
                    // Functions & Thinking popup button
                    id: functionsButton
                    implicitWidth: functionsButtonRow.implicitWidth + 12
                    implicitHeight: functionsButtonRow.implicitHeight + 8
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    onClicked: functionsPopup.toggle()

                    contentItem: RowLayout {
                        id: functionsButtonRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "service_toolbox"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3onSurface
                            text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                            elide: Text.ElideRight
                        }
                        // Show thinking indicator inline if active
                        Rectangle {
                            visible: {
                                const style = Ai.currentThinkingStyle;
                                return (style === "anthropic" && Ai.thinkingEnabled && Ai.thinkingLevel > 0)
                                    || (style === "gemini" && Ai.thinkingLevel > 0);
                            }
                            width: thinkingInlineLabel.implicitWidth + 6
                            height: thinkingInlineLabel.implicitHeight + 2
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3primary
                            opacity: 0.8
                            StyledText {
                                id: thinkingInlineLabel
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller - 2
                                color: Appearance.m3colors.m3onPrimary
                                text: {
                                    const style = Ai.currentThinkingStyle;
                                    if (style === "anthropic") {
                                        const labels = ["", "L", "M", "H"];
                                        return "T:" + labels[Ai.thinkingLevel];
                                    } else if (style === "gemini") {
                                        const labels = ["", "L", "M", "H"];
                                        return "T:" + labels[Ai.thinkingLevel];
                                    }
                                    return "";
                                }
                            }
                        }
                        MaterialSymbol {
                            text: "expand_more"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ButtonGroup {
                    // Command buttons
                    padding: 0

                    Repeater {
                        // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation);
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ");
                                    messageInputField.cursorPosition = messageInputField.text.length;
                                    messageInputField.forceActiveFocus();
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
