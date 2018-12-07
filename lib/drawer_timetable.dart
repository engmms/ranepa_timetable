import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:ranepa_timetable/localizations.dart';
import 'package:ranepa_timetable/search.dart';
import 'package:ranepa_timetable/timeline_model.dart';
import 'package:ranepa_timetable/timetable.dart';
import 'package:ranepa_timetable/timetable_lesson.dart';
import 'package:ranepa_timetable/timetable_room.dart';
import 'package:ranepa_timetable/timetable_teacher.dart';
import 'package:ranepa_timetable/widget_templates.dart';
import 'package:xml/xml.dart' as xml;

class DrawerTimetable extends StatelessWidget {
  final Drawer drawer;

  Search _searchDelegate;

  static const channel = const BasicMessageChannel(
      'ru.coolone.ranepatimetable/jsonChannel', StringCodec());

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const tabCount = 6;

  DrawerTimetable({Key key, this.drawer}) : super(key: key);

  Future<void> channelSet([dynamic args]) async {
    var resp;
    List<String> jsons = [];

    for (var mArg in args) {
      final str = json.encode(mArg);
      print('Call add on: ' + str);

      jsons.add(str);
    }

    try {
      debugPrint("Channel req.. args: ${jsons.toString()}");
      resp = await channel.send(jsons.toString());
    } on PlatformException catch (e) {
      resp = e.message;
    }

    debugPrint("Get resp: " + resp.toString());
  }

  @override
  Widget build(BuildContext context) {
    _searchDelegate = Search(context);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month,
        now.weekday == DateTime.sunday ? now.day + 1 : now.day); // skip sunday

    final weekdayNames = [
      AppLocalizations.of(context).monday,
      AppLocalizations.of(context).tuesday,
      AppLocalizations.of(context).wednesday,
      AppLocalizations.of(context).thursday,
      AppLocalizations.of(context).friday,
      AppLocalizations.of(context).saturday
    ];

    final tabs = List<Tab>();
    var _tabCount = tabCount;
    for (int mTabId = 0; mTabId < _tabCount; mTabId++) {
      debugPrint("mTabId: " + mTabId.toString());
      final mDay = today.add(Duration(days: mTabId));
      debugPrint("mDay: " + mDay.day.toString());
      debugPrint("mWeekday: " + mDay.weekday.toString());
      if (mDay.weekday == DateTime.sunday) {
        debugPrint("Skippin sunday");
        // Skip day
        _tabCount++;
        continue;
      }
      tabs.add(Tab(
        text: weekdayNames[mDay.weekday - 1],
      ));
    }

    return DefaultTabController(
      length: tabCount,
      child: StreamBuilder<SearchItem>(
        stream: timetableIdBloc.stream,
        initialData: _searchDelegate.predefinedSuggestions[3],
        builder: (context, snapshot) => Scaffold(
              drawer: drawer,
              key: _scaffoldKey,
              body: FutureBuilder(
                future: http.post(
                    'http://test.ranhigs-nn.ru/api/WebService.asmx',
                    headers: {'Content-Type': 'text/xml; charset=utf-8'},
                    body: '''
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <GetRaspGroup xmlns="http://tempuri.org/">
      <d1>${today.toIso8601String()}</d1>
      <d2>${today.add(Duration(days: tabCount - 1)).toIso8601String()}</d2>
      <id>${snapshot.data.id}</id>
    </GetRaspGroup>
  </soap:Body>
</soap:Envelope>
''').then((response) => response.body),
                builder: (context, snapshot) {
                  debugPrint("started builder: " +
                      snapshot.connectionState.toString());
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.active:
                    case ConnectionState.waiting:
                      return WidgetTemplates.buildLoading(context);
                      break;
                    case ConnectionState.done:
                      if (snapshot.hasError)
                        return WidgetTemplates.buildErrorMessage(context, snapshot.error);

                      final itemArr = xml
                          .parse(snapshot.data)
                          .children[1]
                          .firstChild
                          .firstChild
                          .firstChild
                          .children;

                      final List<List<TimelineModel>> tabsLessonsList = [];
                      for (int mTabId = 0; mTabId < tabCount; mTabId++) {
                        tabsLessonsList.add(List<TimelineModel>());
                      }

                      var mDate = today;
                      var mTabId = 0;
                      for (var mItemId = 0;
                          mItemId < itemArr.length;
                          mItemId++) {
                        var mItem = itemArr[mItemId];

                        final mItemTimeStart = mItem
                            .children[TimetableResponseIndexes.TimeStart.index]
                            .text;
                        final mItemTimeFinish = mItem
                            .children[TimetableResponseIndexes.TimeFinish.index]
                            .text;
                        final mItemDate = DateTime.parse(mItem
                            .children[TimetableResponseIndexes.Date.index]
                            .text);

                        var dateAppend = mItemDate != mDate;
                        if (dateAppend) {
                          mTabId++;
                          do {
                            mDate = mDate.add(Duration(days: 1));
                          } while (mItemDate != mDate); // skips sundays
                        }

                        tabsLessonsList[mTabId].add(TimelineModel(
                            date: mItemDate,
                            start: TimeOfDay(
                                hour: int.parse(mItemTimeStart.substring(
                                    0, mItemTimeStart.length - 3)),
                                minute: int.parse(mItemTimeStart.substring(
                                    mItemTimeStart.length - 2,
                                    mItemTimeStart.length))),
                            finish: TimeOfDay(
                                hour: int.parse(mItemTimeFinish.substring(
                                    0, mItemTimeFinish.length - 3)),
                                minute: int.parse(
                                    mItemTimeFinish.substring(mItemTimeFinish.length - 2, mItemTimeFinish.length))),
                            room: RoomModel.fromString(mItem.children[TimetableResponseIndexes.Room.index].text),
                            group: mItem.children[TimetableResponseIndexes.Group.index].text,
                            lesson: LessonModel.fromString(context, mItem.children[TimetableResponseIndexes.Name.index].text),
                            teacher: TeacherModel.fromString(mItem.children[TimetableResponseIndexes.Name.index].text)));
                      }

                      for (var mTab in tabsLessonsList) {
                        mTab.first.first = true;
                        mTab.last.last = true;

                        // TODO: detect lesson merge etc.
                      }

                      if (tabsLessonsList.isNotEmpty)
                        channelSet(tabsLessonsList.expand((f) => f).toList());

                      final tabViews = List<Widget>();
                      for (var mTab in tabsLessonsList) {
                        tabViews.add(TimetableWidget(lessons: mTab));
                      }

                      return TabBarView(children: tabViews);
                  }
                  return null; // unreachable
                },
              ),
              appBar: AppBar(
                elevation:
                    defaultTargetPlatform == TargetPlatform.android ? 5 : 0,
                title: Text(snapshot.data.title),
                actions: <Widget>[
                  IconButton(
                    tooltip: AppLocalizations.of(context).searchTip,
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () {},
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).searchTip,
                    icon: const Icon(Icons.alarm),
                    onPressed: () {},
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).searchTip,
                    icon: const Icon(Icons.search),
                    onPressed: () => showSearch<SearchItem>(
                          context: context,
                          delegate: _searchDelegate,
                        ),
                  ),
                ],
                bottom: TabBar(
                  tabs: tabs,
                ),
              ),
            ),
      ),
    );
  }
}

final timetableIdBloc = StreamController<SearchItem>.broadcast();
