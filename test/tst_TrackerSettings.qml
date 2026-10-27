// Run from a hal-c2 checkout, with QT_QPA_PLATFORM=offscreen:
//   qmltestrunner -import apps/desktop-qt/tests/imports -import apps/desktop-qt/qml \
//     -input <this plugin>/test/tst_TrackerSettings.qml
import QtQuick
import QtTest

// A TestCase is never visible, so what it clicks lives beside it.
Item {
    id: test

    width: 700
    height: 1600

    readonly property var saved: ({
            ledger: "hal-c2/hal-c2",
            upstream: "pingdotgg/t3code",
            pollMinutes: 30,
            checking: {
                provider: "claudeAgent",
                model: "claude-opus-5-5",
                modelOptions: {
                    effort: "high"
                },
                runtimeMode: "auto-accept-edits"
            },
            checkPrompt: "Ledger {{upstream}}.",
            implementing: {
                provider: "claudeAgent",
                model: "",
                modelOptions: {},
                runtimeMode: "full-access"
            },
            implementPrompt: "Make {{file}} pass."
        })

    readonly property var providers: [
        {
            instanceId: "claudeAgent",
            name: "Claude",
            models: [
                {
                    slug: "claude-opus-5-5",
                    name: "Opus 5.5",
                    isDefault: true,
                    options: [
                        {
                            id: "effort",
                            label: "Effort",
                            type: "select",
                            options: [
                                {
                                    id: "medium"
                                },
                                {
                                    id: "high"
                                }
                            ]
                        }
                    ]
                },
                {
                    slug: "claude-sonnet-5-5",
                    name: "Sonnet 5.5",
                    isDefault: false,
                    options: []
                }
            ]
        },
        {
            instanceId: "codex",
            name: "Codex",
            models: [
                {
                    slug: "gpt-6",
                    name: "GPT-6",
                    isDefault: true,
                    options: []
                }
            ]
        }
    ]

    // The plugin object a settings page gets, with the MC part faked: `settings`
    // answers what is saved, and each save is recorded.
    QtObject {
        id: plugin

        property var environments: ["local"]
        property var saves: []

        function call(method, input, callback, environment) {
            callback({
                settings: test.saved,
                providers: test.providers
            }, null);
        }

        function saveSettings(values, callback, environment) {
            saves = saves.concat([values]);
            callback({}, null);
        }
    }

    Loader {
        id: loader

        width: test.width
    }

    TestCase {
        name: "TrackerSettings"
        when: windowShown

        function find(name) {
            return findChild(loader.item, name);
        }

        function init() {
            plugin.saves = [];
            loader.source = "";
            loader.setSource(Qt.resolvedUrl("../ui/TrackerSettings.qml"), {
                plugin: plugin
            });
            tryVerify(() => loader.status === Loader.Ready && loader.item.loaded);
        }

        function test_each_agent_shows_its_own_pick() {
            compare(find("t3codeTrackerSetting:checking:model").displayText, "Opus 5.5");
            compare(find("t3codeTrackerSetting:implementing:model").displayText, "Its default model");
            compare(find("t3codeTrackerSetting:checking:modelOption:effort").visible, true);
        }

        function test_another_agent_for_implementing_leaves_checking_alone() {
            find("t3codeTrackerSetting:implementing:provider").activated(1);
            mouseClick(find("t3codeTrackerSave"));
            compare(plugin.saves.length, 1);
            compare(plugin.saves[0].implementing, {
                provider: "codex",
                model: "",
                modelOptions: {},
                runtimeMode: "full-access"
            });
            compare(plugin.saves[0].checking, test.saved.checking);
        }

        function test_another_model_drops_the_options_of_the_last_one() {
            find("t3codeTrackerSetting:checking:model").activated(2);
            mouseClick(find("t3codeTrackerSave"));
            compare(plugin.saves[0].checking, {
                provider: "claudeAgent",
                model: "claude-sonnet-5-5",
                modelOptions: {},
                runtimeMode: "auto-accept-edits"
            });
        }
    }
}
