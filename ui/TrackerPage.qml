pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HalC2.Shell
import HalC2.Bricks

// The Upstream page: the upstream T3 Code pull requests the ledger's scenarios
// cite, by whether that work is still being done, and the one picked with who
// wrote it and the feature files that cite it; or everyone credited across them.
// Follows the `ledger` topic of each MC that runs the tracker, one MC at a time.
Item {
    id: page

    property var plugin
    // environment → the last value of its `ledger` topic.
    property var byEnvironment: ({})
    // environment → its watch.
    property var watches: ({})
    property string environment: ""
    readonly property var ledger: byEnvironment[environment] ?? null
    readonly property var order: ["working", "blocked", "finished", "dropped", "cited"]
    readonly property var pullRequests: (ledger?.pullRequests ?? []).slice().sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status))
    property string selected: ""
    readonly property var pullRequest: pullRequests.find(each => each.key === selected) ?? null
    // "pullRequests" or "credits".
    property string view: "pullRequests"
    property string refusal: ""
    readonly property color foreground: Theme.palette.color("text", "#e4e4e7")
    readonly property color muted: Theme.palette.color("textMuted", "#a1a1aa")
    readonly property color border: Theme.palette.color("border", "#27272a")
    readonly property color warningColor: Theme.palette.color("warning", "#f59e0b")
    readonly property color successColor: Theme.palette.color("success", "#22c55e")

    function follow() {
        const watches = {};
        for (const environment of page.plugin.environments) {
            watches[environment] = page.watches[environment] ?? page.plugin.watch("ledger", value => {
                const next = Object.assign({}, page.byEnvironment);
                next[environment] = value;
                page.byEnvironment = next;
            }, environment);
        }
        for (const environment of Object.keys(page.watches)) {
            if (watches[environment] === undefined)
                page.plugin.unwatch(page.watches[environment]);
        }
        page.watches = watches;
        if (!page.plugin.environments.includes(page.environment))
            page.environment = page.plugin.environments[0] ?? "";
    }

    function refresh() {
        page.refusal = "";
        page.plugin.call("refresh", {}, (result, error) => {
            if (error)
                page.refusal = error;
        }, page.environment);
    }

    function environmentLabel(environment) {
        const known = (Shell.state.mcPlugins?.environments ?? []).find(each => each.id === environment);
        return known?.label ?? environment;
    }

    function statusText(status) {
        switch (status) {
        case "working":
            return qsTr("Being worked on");
        case "blocked":
            return qsTr("Blocked");
        case "finished":
            return qsTr("Finished");
        case "dropped":
            return qsTr("Dropped");
        default:
            return qsTr("Cited, no scenarios");
        }
    }

    function statusColor(status) {
        if (status === "finished")
            return page.successColor;
        if (status === "blocked")
            return page.warningColor;
        return page.muted;
    }

    // "927 of 2,173 scenarios finished", leaving out the dropped ones.
    function progress(scenarios) {
        const counted = scenarios.finished + scenarios.working + scenarios.blocked;
        return qsTr("%1 of %2 scenarios finished").arg(scenarios.finished.toLocaleString()).arg(counted.toLocaleString());
    }

    function people(list) {
        return list.filter(person => !person.bot);
    }

    function byline(pullRequest) {
        if (!pullRequest.author)
            return qsTr("Not on upstream's main");
        const others = page.people(pullRequest.coAuthors).length;
        return others > 0 ? qsTr("%1 and %2 more").arg(pullRequest.author.name).arg(others) : pullRequest.author.name;
    }

    // A person's name as styled text, linked to their GitHub profile when their
    // address names it.
    function personText(person) {
        const name = person.name.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return person.login ? "<a href=\"https://github.com/%1\">%2</a>".arg(encodeURIComponent(person.login)).arg(name) : name;
    }

    function date(value) {
        return value ? Qt.formatDate(new Date(value), Qt.locale().dateFormat(Locale.ShortFormat)) : "";
    }

    objectName: "t3codeTrackerPage"
    implicitWidth: 900
    implicitHeight: 600
    onPullRequestsChanged: if (pullRequest === null && pullRequests.length > 0)
        selected = pullRequests[0].key
    Component.onCompleted: follow()

    Connections {
        target: page.plugin

        function onEnvironmentsChanged() {
            page.follow();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // What is followed, how far the ledger has read, and the two views.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: bar.implicitHeight + 20
            color: Theme.palette.color("surface", "#18181b")

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: page.border
            }

            ColumnLayout {
                id: bar

                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        objectName: "t3codeTrackerFollowing"
                        Layout.fillWidth: true
                        text: {
                            if (page.ledger === null)
                                return qsTr("Waiting for the tracker…");
                            const parts = [qsTr("Following %1 %2").arg(page.ledger.upstream).arg(page.ledger.branch)];
                            const cursor = page.ledger.cursor;
                            if (cursor)
                                parts.push(cursor.pending === null || cursor.pending === undefined ? qsTr("ledger read through %1").arg(cursor.commit.slice(0, 10)) : (cursor.pending === 1 ? qsTr("ledger read through %1, 1 upstream commit after it not read yet").arg(page.date(cursor.date)) : qsTr("ledger read through %1, %2 upstream commits after it not read yet").arg(page.date(cursor.date)).arg(cursor.pending)));
                            if (page.ledger.looking)
                                parts.push(qsTr("looking…"));
                            return parts.join("  ·  ");
                        }
                        color: page.muted
                        elide: Text.ElideRight
                        font.pixelSize: Math.round(12 * Theme.fontScale)
                    }

                    ShellComboBox {
                        visible: page.plugin.environments.length > 1
                        outline: true
                        implicitWidth: 180
                        model: page.plugin.environments.map(environment => page.environmentLabel(environment))
                        currentIndex: page.plugin.environments.indexOf(page.environment)
                        Accessible.name: qsTr("Machine")
                        onActivated: index => page.environment = page.plugin.environments[index]
                    }

                    ShellButton {
                        objectName: "t3codeTrackerPullRequests"
                        subtle: page.view !== "pullRequests"
                        text: qsTr("Pull requests")
                        onClicked: page.view = "pullRequests"
                    }

                    ShellButton {
                        objectName: "t3codeTrackerCredits"
                        subtle: page.view !== "credits"
                        text: qsTr("Credits")
                        onClicked: page.view = "credits"
                    }

                    ShellButton {
                        objectName: "t3codeTrackerRefresh"
                        subtle: true
                        enabled: page.ledger !== null && !page.ledger.looking
                        text: qsTr("Look now")
                        onClicked: page.refresh()
                    }
                }

                Text {
                    objectName: "t3codeTrackerProblem"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: page.refusal || (page.ledger?.problem ?? "")
                    color: page.warningColor
                    wrapMode: Text.Wrap
                    font.pixelSize: Math.round(12 * Theme.fontScale)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.view === "pullRequests"
            spacing: 0

            ListView {
                id: list

                objectName: "t3codeTrackerList"
                Layout.preferredWidth: Math.min(400, page.width * 0.42)
                Layout.fillHeight: true
                clip: true
                model: page.pullRequests
                currentIndex: page.pullRequests.findIndex(each => each.key === page.selected)
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: if (currentIndex >= 0 && activeFocus)
                    page.selected = page.pullRequests[currentIndex].key

                ScrollBar.vertical: ScrollBar {}

                delegate: Column {
                    id: entry

                    required property var modelData
                    required property int index

                    width: ListView.view.width

                    // The first pull request of a status names it.
                    Text {
                        width: entry.width
                        visible: entry.index === 0 || page.pullRequests[entry.index - 1].status !== entry.modelData.status
                        leftPadding: 16
                        topPadding: entry.index > 0 ? 14 : 10
                        bottomPadding: 4
                        text: page.statusText(entry.modelData.status)
                        color: page.muted
                        font.pixelSize: Math.round(11 * Theme.fontScale)
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                    }

                    ItemDelegate {
                        id: row

                        readonly property var modelData: entry.modelData

                        objectName: "t3codeTracker:" + modelData.key
                        width: entry.width
                        leftPadding: 16
                        rightPadding: 12
                        topPadding: 6
                        bottomPadding: 6
                        highlighted: modelData.key === page.selected
                        Accessible.name: qsTr("%1 %2, %3").arg(modelData.key).arg(modelData.title ?? "").arg(page.statusText(modelData.status))
                        onClicked: {
                            page.selected = modelData.key;
                            list.currentIndex = entry.index;
                            list.forceActiveFocus();
                        }

                        background: Rectangle {
                            color: row.highlighted ? Theme.palette.color("sidebarRowSelected", "#27272a") : row.hovered ? Theme.palette.color("sidebarRowHover", "#1f1f23") : "transparent"
                        }

                        contentItem: ColumnLayout {
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.key + "  " + (row.modelData.title ?? "")
                                color: page.foreground
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(13 * Theme.fontScale)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: page.byline(row.modelData) + " · " + page.progress(row.modelData.scenarios)
                                color: page.muted
                                elide: Text.ElideRight
                                font.pixelSize: Math.round(11 * Theme.fontScale)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    visible: page.pullRequests.length === 0 && page.ledger !== null && !page.ledger.looking
                    text: qsTr("No feature file of the ledger cites an upstream pull request yet.")
                    color: page.muted
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Math.round(13 * Theme.fontScale)
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: page.border
            }

            // The pull request picked in the list.
            Flickable {
                id: detail

                objectName: "t3codeTrackerDetail"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: about.implicitHeight + 32
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: about

                    readonly property var pullRequest: page.pullRequest

                    x: 20
                    y: 16
                    width: detail.width - 40
                    visible: pullRequest !== null
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: about.pullRequest ? about.pullRequest.key + "  " + (about.pullRequest.title ?? "") : ""
                        color: page.foreground
                        wrapMode: Text.Wrap
                        font.pixelSize: Math.round(16 * Theme.fontScale)
                        font.weight: Font.Medium
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const pullRequest = about.pullRequest;
                                if (!pullRequest)
                                    return "";
                                const parts = [page.statusText(pullRequest.status), page.progress(pullRequest.scenarios)];
                                if (pullRequest.scenarios.dropped > 0)
                                    parts.push(qsTr("%n dropped", "", pullRequest.scenarios.dropped));
                                if (pullRequest.mergedAt)
                                    parts.push(qsTr("merged %1").arg(page.date(pullRequest.mergedAt)));
                                return parts.join(" · ");
                            }
                            color: page.statusColor(about.pullRequest?.status ?? "")
                            wrapMode: Text.Wrap
                            font.pixelSize: Math.round(12 * Theme.fontScale)
                        }

                        ShellButton {
                            subtle: true
                            text: qsTr("Open on GitHub")
                            onClicked: Qt.openUrlExternally(about.pullRequest.url)
                        }
                    }

                    Text {
                        text: qsTr("Written by")
                        color: page.muted
                        font.pixelSize: Math.round(11 * Theme.fontScale)
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                    }

                    Text {
                        objectName: "t3codeTrackerAuthors"
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        linkColor: Theme.link
                        text: {
                            const pullRequest = about.pullRequest;
                            if (!pullRequest?.author)
                                return qsTr("This is not on upstream's main, so who wrote it is not known here.");
                            const people = [pullRequest.author].concat(page.people(pullRequest.coAuthors));
                            return people.map(person => page.personText(person)).join(", ");
                        }
                        color: page.foreground
                        wrapMode: Text.Wrap
                        font.pixelSize: Math.round(13 * Theme.fontScale)
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }

                    Text {
                        readonly property var agents: (about.pullRequest?.coAuthors ?? []).filter(person => person.bot)

                        Layout.fillWidth: true
                        visible: agents.length > 0
                        text: qsTr("With agents and bots: %1").arg(agents.map(person => person.name).join(", "))
                        color: page.muted
                        wrapMode: Text.Wrap
                        font.pixelSize: Math.round(12 * Theme.fontScale)
                    }

                    Text {
                        text: qsTr("Cited by")
                        color: page.muted
                        font.pixelSize: Math.round(11 * Theme.fontScale)
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                    }

                    Repeater {
                        model: about.pullRequest?.files ?? []

                        delegate: ColumnLayout {
                            id: file

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: file.modelData.path
                                color: page.foreground
                                elide: Text.ElideMiddle
                                font.family: Theme.fontMono.length > 0 ? Theme.fontMono : "monospace"
                                font.pixelSize: Math.round(12 * Theme.fontScale)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: [page.progress(file.modelData.scenarios), file.modelData.note].filter(part => part).join(" · ")
                                color: page.muted
                                wrapMode: Text.Wrap
                                font.pixelSize: Math.round(11 * Theme.fontScale)
                            }
                        }
                    }
                }
            }
        }

        // Everyone whose upstream work the ledger carries, most cited first.
        ListView {
            id: credits

            objectName: "t3codeTrackerCreditList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.view === "credits"
            clip: true
            model: page.ledger?.credits ?? []
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {}

            header: Text {
                width: credits.width
                padding: 16
                text: qsTr("The people who wrote the upstream pull requests the ledger cites, authors and co-authors alike. Agents and bots are left out here; each pull request still names them.")
                color: page.muted
                wrapMode: Text.Wrap
                font.pixelSize: Math.round(12 * Theme.fontScale)
            }

            delegate: RowLayout {
                id: credit

                required property var modelData

                x: 16
                width: credits.width - 32
                height: implicitHeight + 8
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    linkColor: Theme.link
                    text: page.personText(credit.modelData)
                    color: page.foreground
                    elide: Text.ElideRight
                    font.pixelSize: Math.round(13 * Theme.fontScale)
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }

                Text {
                    text: credit.modelData.entries.join(", ")
                    color: page.muted
                    font.pixelSize: Math.round(12 * Theme.fontScale)
                }
            }
        }
    }
}
