import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Widgets

Item {
    id: root

    property string providerId: ""
    property string fallbackIcon: "monitoring"
    property color tintColor: Theme.surfaceText
    property int logoSize: 20

    readonly property string canonicalId: {
        const aliases = {
            agy: "antigravity",
            moonshot: "kimi",
            zhipu: "glm",
            dashscope: "qwen",
            alibaba: "qwen",
            nim: "nvidia",
            vertex: "vertexai",
            ark: "byteplus",
            modelark: "byteplus",
            grok: "xai"
        };
        const normalized = String(providerId || "").trim().toLowerCase();
        return aliases[normalized] || normalized;
    }
    readonly property var colorLogoIds: [
        "9router", "ai21", "amp", "antigravity", "byteplus", "claude",
        "cloudflare", "cohere", "copilot", "deepseek", "fireworks",
        "gemini", "glm", "kimi", "kiro", "minimax", "mistral",
        "nvidia", "perplexity", "qwen", "together", "vertexai", "warp"
    ]
    readonly property bool usesBrandColors: colorLogoIds.indexOf(canonicalId) >= 0
    readonly property string logoExtension: canonicalId === "byteplus" ? ".png" : ".svg"
    readonly property url logoSource: canonicalId.length > 0
        ? Qt.resolvedUrl("assets/provider-logos/" + canonicalId + logoExtension)
        : ""
    readonly property bool logoReady: logoImage.status === Image.Ready

    implicitWidth: logoSize
    implicitHeight: logoSize
    width: logoSize
    height: logoSize

    Image {
        id: logoImage
        anchors.centerIn: parent
        width: root.logoSize
        height: root.logoSize
        source: root.logoSource
        sourceSize: Qt.size(root.logoSize * 2, root.logoSize * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
        visible: root.usesBrandColors && root.logoReady
    }

    MultiEffect {
        anchors.fill: logoImage
        source: logoImage
        visible: !root.usesBrandColors && root.logoReady
        colorization: 1.0
        colorizationColor: root.tintColor
    }

    DankIcon {
        anchors.centerIn: parent
        visible: root.logoSource.toString().length === 0 || logoImage.status === Image.Error
        name: root.fallbackIcon
        size: root.logoSize
        color: root.tintColor
    }
}
