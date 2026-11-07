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
            backlog: [
                {
                    path: "features/threads/pin.feature",
                    scenarios: {
                        finished: 1,
                        working: 2,
                        blocked: 0,
                        dropped: 0
                    },
                    surfaces: {
                        mc: 0,
                        desktop: 2,
                        mobile: 1,
                        tui: 0
                    },
                    priority: {
                        high: 1,
                        low: 0
                    }
                },
                {
                    path: "features/threads/snooze.feature",
                    scenarios: {
                        finished: 10,
                        working: 4,
                        blocked: 1,
                        dropped: 0
                    },
                    surfaces: {
                        mc: 4,
                        desktop: 0,
                        mobile: 0,
                        tui: 0
                    },
                    priority: {
                        high: 0,
                        low: 0
                    }
                },
                {
                    path: "features/threads/waiting.feature",
                    scenarios: {
                        finished: 0,
                        working: 0,
                        blocked: 2,
                        dropped: 0
                    },
                    surfaces: {
                        mc: 0,
                        desktop: 0,
                        mobile: 0,
                        tui: 0
                    },
                    priority: {
                        high: 0,
                        low: 0
                    }
                }
            ],
            work: [
                {
                    branch: "snooze-ends",
                    at: 3,
                    pullRequest: {
                        number: 1100,
                        title: "feat: snoozes end <on time>",
                        url: "https://github.com/hal-c2/hal-c2/pull/1100",
                        draft: true
                    },
                    files: [
                        {
                            path: "features/threads/snooze.feature",
                            scenarios: 2,
                            finishes: 1
                        }
                    ]
                },
                {
                    branch: "tidy/pin",
                    at: 2,
                    pullRequest: null,
                    files: [
                        {
                            path: "features/threads/pin.feature",
                            scenarios: 0,
                            finishes: 0
                        }
                    ]
                }
            ],
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
                    exact: true,
                    work: [],
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
                            scope: "scoped",
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
                    exact: false,
                    work: ["snooze-ends"],
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
                            scope: "file",
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
                            scope: "file",
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
            waitForRendering(loader.item);
        }

        // Shows `view` once its layout has settled, so clicks land where they look.
        function show(view) {
            loader.item.view = view;
            waitForRendering(loader.item);
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
            show("pullRequests");
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
            show("pullRequests");
            const check = find("t3codeTrackerCheckThread");
            compare(check.text, "Last check: done");
            mouseClick(check);
            const running = findChild(find("t3codeTrackerFile:features/threads/snooze.feature"), "t3codeTrackerImplementThread");
            compare(running.text, "Implementing: running");
            mouseClick(running);
            compare(plugin.opened, ["local/t-check", "local/t-snooze"]);
            verify(!findChild(find("t3codeTrackerFile:features/threads/archive.feature"), "t3codeTrackerImplementThread").visible);
        }

        function test_the_backlog_lists_every_file_with_work_left_cited_or_not() {
            compare(loader.item.view, "backlog");
            const pin = find("t3codeTrackerBacklog:features/threads/pin.feature");
            verify(pin);
            const counts = findChild(pin, "t3codeTrackerBacklogCounts").text;
            compare(counts, "2 to do · 1 finished · missing on desktop 2, mobile 1 · 1 high priority");
            // Nothing upstream cites pin.feature, and it can still be implemented.
            mouseClick(findChild(pin, "t3codeTrackerImplement"));
            compare(plugin.calls, [
                {
                    method: "implement",
                    input: {
                        path: "features/threads/pin.feature"
                    }
                }
            ]);
            const waiting = find("t3codeTrackerBacklog:features/threads/waiting.feature");
            verify(!findChild(waiting, "t3codeTrackerImplement").visible);
            compare(findChild(waiting, "t3codeTrackerBacklogCounts").text, "0 to do · 2 blocked · 0 finished");
        }

        function test_a_file_shows_the_branches_and_pull_requests_at_work_on_it() {
            const snooze = findChild(find("t3codeTrackerBacklog:features/threads/snooze.feature"), "t3codeTrackerAtWork");
            verify(snooze.visible);
            compare(snooze.text, "At work: <a href=\"https://github.com/hal-c2/hal-c2/pull/1100\">#1100</a> feat: snoozes end &lt;on time&gt; (draft), 2 of its backlog scenarios changed, 1 passing");
            const pin = findChild(find("t3codeTrackerBacklog:features/threads/pin.feature"), "t3codeTrackerAtWork");
            compare(pin.text, "At work: <a href=\"https://github.com/hal-c2/hal-c2/tree/tidy/pin\">tidy/pin</a>, editing the file");
            verify(!findChild(find("t3codeTrackerBacklog:features/threads/waiting.feature"), "t3codeTrackerAtWork").visible);
        }

        function test_the_branches_at_work_are_listed_with_what_they_change() {
            mouseClick(find("t3codeTrackerWorkView"));
            compare(find("t3codeTrackerWorkView").text, "In progress (2)");
            tryVerify(() => find("t3codeTrackerBranch:snooze-ends") !== null);
            verify(find("t3codeTrackerBranch:tidy/pin"));
        }

        function test_a_pull_request_cited_for_a_whole_file_says_so_and_shows_its_work() {
            mouseClick(find("t3codeTrackerPullRequests"));
            compare(loader.item.selected, "#2829");
            verify(find("t3codeTrackerWholeFile").visible);
            verify(find("t3codeTrackerEntryWork").text.includes("#1100"), find("t3codeTrackerEntryWork").text);
            verify(findChild(find("t3codeTrackerFile:features/threads/snooze.feature"), "t3codeTrackerFileCounts").text.includes("whole file"));
            loader.item.selected = "#9514";
            verify(!find("t3codeTrackerWholeFile").visible);
            verify(!find("t3codeTrackerEntryWork").visible);
            const signIn = findChild(find("t3codeTrackerFile:features/providers/antigravity.feature"), "t3codeTrackerFileCounts").text;
            compare(signIn, "3 of 3 scenarios finished · the sign-in link on stderr");
            // antigravity.feature has no backlog, so it is not offered.
            verify(!findChild(find("t3codeTrackerFile:features/providers/antigravity.feature"), "t3codeTrackerImplement").visible);
        }

        function test_an_agent_that_cannot_start_says_why() {
            plugin.refusal = "There is no agent cursor on this MC; pick one in the settings.";
            mouseClick(find("t3codeTrackerCheck"));
            compare(find("t3codeTrackerProblem").text, plugin.refusal);
        }
    }
}
