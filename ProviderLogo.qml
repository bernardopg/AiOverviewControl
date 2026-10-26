import QtQuick
import QtQuick.Effects
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string providerId: ""
    // Single source of truth for the Material fallback icon, keyed by canonical
    // id. Callers pass only providerId; overriding fallbackIcon is no longer
    // needed (kept overridable for edge cases). Previously the widget and
    // settings maintained separate, diverging maps.
    property string fallbackIcon: defaultIcon
    property color tintColor: Theme.surfaceText
    property int logoSize: 20

    readonly property string canonicalId: {
        const aliases = {
            agy: "antigravity",
            moonshot: "kimi",
            "kimi-code": "kimi",
            zhipu: "glm",
            dashscope: "qwen",
            alibaba: "qwen",
            nim: "nvidia",
            vertex: "vertexai",
            ark: "byteplus",
            modelark: "byteplus",
            grok: "xai",
            "anthropic-api": "anthropic",
            "openai-api": "openai",
            "ai-gateway": "vercel"
        };
        const normalized = String(providerId || "").trim().toLowerCase();
        if (/^claude-[a-z0-9][a-z0-9_-]{0,55}$/.test(normalized)) return "claude";
        return aliases[normalized] || normalized;
    }
    readonly property string defaultIcon: {
        const icons = {
            codex: "data_object", claude: "psychology", copilot: "hub", pi: "smart_toy",
            hermes: "hub", antigravity: "rocket_launch", gemini: "auto_awesome", openrouter: "route",
            "9router": "share", deepseek: "tsunami", kimi: "dark_mode", mistral: "air",
            glm: "bubble_chart", minimax: "grid_view", qwen: "cloud", nvidia: "memory",
            cloudflare: "shield", vertexai: "hexagon", byteplus: "bolt",
            perplexity: "travel_explore", cursor: "ads_click", ollama: "dns",
            together: "join_inner", groq: "fast_forward", cohere: "waves",
            replicate: "content_copy", fireworks: "local_fire_department", xai: "bolt",
            ai21: "looks_21", cline: "terminal", commandcode: "terminal", neuralwatt: "energy_savings_leaf", anthropic: "psychology", openai: "data_object", vercel: "change_history", "ollama-cloud": "cloud_queue", opencode: "code", warp: "rocket_launch",
            amp: "electric_bolt", kilo: "speed", kiro: "tune"
        };
        return icons[canonicalId] || "monitoring";
    }
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

        // Applying the colorization to the image layer keeps the original
        // transparent SVG silhouette; do not use it as a sibling effect
        // source, which is opaque with this renderer.
        layer.enabled: true
        layer.effect: MultiEffect {
            brightness: 1.0
            colorization: 1.0
            colorizationColor: root.tintColor
        }
    }

    DIcon {
        anchors.centerIn: parent
        visible: root.logoSource.toString().length === 0 || logoImage.status === Image.Error
        name: root.fallbackIcon
        size: root.logoSize
        color: root.tintColor
    }
}
