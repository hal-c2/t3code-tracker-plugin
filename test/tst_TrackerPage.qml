// Run from a hal-c2 checkout, with QT_QPA_PLATFORM=offscreen:
//   qmltestrunner -import apps/desktop-qt/tests/imports -import apps/desktop-qt/qml \
//     -input <this plugin>/test/tst_TrackerPage.qml
import QtQuick
import QtTest

// A TestCase is never visible, so what it clicks lives beside it.
Item {
    id: test

    width: 900
    height: 600

    readonly property var ledger: ({
            upstream: "pingdotgg/t3code",
            branch: "main",
            ledger: {
                repository: "hal-c2/hal-c2",
                project: "hal-c2",
                root: "/src/hal-c2"
            },
            cursor: {
                commit: "f5ef0ddb90a8c36584e181b1913e7b8a5df30ffc",
                date: "2026-09-23T10:00:00Z",
                pending: 3577
            },
            looking: false,
            problem: null,
            threads: {
                "check": {
                    threadId: "t-check",
                    startedAt: 1,
                    status: "completed"
                },
                "implement:features/threads/snooze.feature": {
                    threadId: "t-snooze",
                    startedAt: 2,
                    status: "running"
                }
            },
            pullRequests: [
                {
                    key: "#9514",
                    number: 9514,
                    title: "fix(antigravity): handle native sign-in URLs on stderr",
                    url: "https://github.com/pingdotgg/t3code/pull/9514",
                    status: "finished",
                    onBranch: true,
                    mergedAt: "2026-09-03T16:39:17-07:00",
                    author: {
                        name: "Theo Browne",
                        email: "me@t3.gg",
                        login: null,
                        bot: false
                    },
                    coAuthors: [],
                    scenarios: {
                        finished: 3,
                        working: 0,
                        blocked: 0,
                        dropped: 1
                    },
                    files: [
                        {
                            path: "features/providers/antigravity.feature",
                            note: "the sign-in link on stderr",
                            scenarios: {
                                finished: 3,
                                working: 0,
                                blocked: 0,
                                dropped: 1
                            }
                        }
                    ]
                },
                {
                    key: "#2829",
                    number: 2829,
                    title: "feat(orchestrator): introduce new orchestrator",
                    url: "https://github.com/pingdotgg/t3code/pull/2829",
                    status: "working",
                    onBranch: true,
                    mergedAt: "2026-10-02T12:22:22-07:00",
                    author: {
                        name: "Julius Marminge",
                        email: "julius0216@outlook.com",
                        login: null,
                        bot: false
                    },
                    coAuthors: [
                        {
                            name: "Bilal <Bakr>",
                            email: "62337003+bil0000@users.noreply.github.com",
                            login: "Bil0000",
                            bot: false
                        },
                        {
                            name: "Claude Opus 5 (1M context)",
                            email: "noreply@anthropic.com",
                            login: null,
                            bot: true
                        }
                    ],
                    scenarios: {
                        finished: 927,
                        working: 1244,
                        blocked: 2,
                        dropped: 6
                    },
                    files: [
                        {
                            path: "features/threads/snooze.feature",
                            note: "",
                            scenarios: {
                                finished: 10,
                                working: 4,
                                blocked: 0,
                                dropped: 0
                            }
                        },
                        {
                            path: "features/threads/archive.feature",
                            note: "",
                            scenarios: {
                                finished: 6,
                                working: 0,
                                blocked: 0,
                                dropped: 0
                            }
                        }
                    ]
                }
            ],
            credits: [
                {
                    name: "Julius Marminge",
                    login: null,
                    entries: ["#2829"]
                },
                {
                    name: "Bilal <Bakr>",
                    login: "Bil0000",
                    entries: ["#2829"]
                }
            ]
        })

    // The plugin object a page gets, with the MC part faked: `ledger` is what it
    // publishes, each call is recorded and answered with `refusal`, and each thread
    // opened is recorded.
    QtObject {
        id: plugin

        property var environments: ["local"]
        property var watchers: ({})
        property var calls: []
        property string refusal: ""
        property var opened: []

        function watch(topic, callback, environment) {
            watchers[environment + "/" + topic] = callback;
            return environment + "/" + topic;
        }

        function unwatch(handle) {
        }

        function call(method, input, callback, environment) {
            calls = calls.concat([
                {
                    method: method,
                    input: input
                }
            ]);
            callback(null, refusal || null);
        }

        function openThread(threadId, environment) {
            opened = opened.concat([environment + "/" + threadId]);
        }

        function publish(value) {
            watchers["local/ledger"](value);
        }
    }

    Loader {
        id: loader

        width: test.width
        height: test.height
    }

    TestCase {
        name: "TrackerPage"
        when: windowShown

        function find(name) {
            return findChild(loader.item, name);
        }

        function init() {
            plugin.watchers = {};
            plugin.calls = [];
            plugin.opened = [];
            plugin.refusal = "";
            // A fresh page each time: setting the same source again keeps the old one.
            loader.source = "";
            loader.setSource(Qt.resolvedUrl("../ui/TrackerPage.qml"), {
                plugin: plugin
            });
            tryVerify(() => loader.status === Loader.Ready && plugin.watchers["local/ledger"] !== undefined);
            plugin.publish(test.ledger);
        }

        function test_work_still_being_done_comes_before_finished_work() {
            compare(loader.item.pullRequests.map(each => each.key), ["#2829", "#9514"]);
            compare(loader.item.selected, "#2829");
            verify(find("t3codeTrackerFollowing").text.includes("3577 upstream commits after it not read yet"), find("t3codeTrackerFollowing").text);
        }

        function test_the_authors_are_people_and_the_agents_are_named_apart() {
            const authors = find("t3codeTrackerAuthors").text;
            verify(authors.includes("Julius Marminge"), authors);
            verify(authors.includes("<a href=\"https://github.com/Bil0000\">Bilal &lt;Bakr&gt;</a>"), authors);
            verify(!authors.includes("Claude"), authors);
        }

        function test_a_pull_request_not_on_main_has_no_authors_to_credit() {
            const unknown = Object.assign({}, test.ledger.pullRequests[0], {
                key: "#1",
                status: "working",
                onBranch: false,
                author: null,
                title: null,
                mergedAt: null
            });
            plugin.publish(Object.assign({}, test.ledger, {
                pullRequests: [unknown]
            }));
            compare(find("t3codeTrackerAuthors").text, "This is not on upstream's main, so who wrote it is not known here.");
        }

        function test_a_problem_shows() {
            plugin.publish(Object.assign({}, test.ledger, {
                problem: "No project on this MC has hal-c2/hal-c2 as its remote."
            }));
            compare(find("t3codeTrackerProblem").text, "No project on this MC has hal-c2/hal-c2 as its remote.");
        }

        function test_only_a_file_with_backlog_scenarios_can_be_implemented() {
            const snooze = find("t3codeTrackerFile:features/threads/snooze.feature");
            const archive = find("t3codeTrackerFile:features/threads/archive.feature");
            verify(findChild(snooze, "t3codeTrackerImplement").visible);
            verify(!findChild(archive, "t3codeTrackerImplement").visible);
            mouseClick(findChild(snooze, "t3codeTrackerImplement"));
            compare(plugin.calls, [
                {
                    method: "implement",
                    input: {
                        path: "features/threads/snooze.feature"
                    }
                }
            ]);
        }

        function test_the_threads_started_show_how_they_went_and_open() {
            const check = find("t3codeTrackerCheckThread");
            compare(check.text, "Last check: done");
            mouseClick(check);
            const running = findChild(find("t3codeTrackerFile:features/threads/snooze.feature"), "t3codeTrackerImplementThread");
            compare(running.text, "Implementing: running");
            mouseClick(running);
            compare(plugin.opened, ["local/t-check", "local/t-snooze"]);
            verify(!findChild(find("t3codeTrackerFile:features/threads/archive.feature"), "t3codeTrackerImplementThread").visible);
        }

        function test_an_agent_that_cannot_start_says_why() {
            plugin.refusal = "There is no agent cursor on this MC; pick one in the settings.";
            mouseClick(find("t3codeTrackerCheck"));
            compare(find("t3codeTrackerProblem").text, plugin.refusal);
        }
    }
}
