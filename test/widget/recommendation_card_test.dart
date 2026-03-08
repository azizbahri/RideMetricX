// Widget tests for RecommendationCard, RecommendationsPanel, and the
// AnalysisScreen recommendations integration (FR-UI-007).
//
// Covers:
//  • RecommendationCard renders severity badge and title
//  • Rationale is hidden initially and visible after tap
//  • Apply button fires the onApply callback with suggestedParameters
//  • Apply button is absent when suggestedParameters is null
//  • RecommendationsPanel lists all cards sorted as provided
//  • RecommendationsPanel shows "no issues" message when list is empty
//  • AnalysisScreen shows RecommendationsPanel when recommendations provided
//  • Integration: apply action propagates through AnalysisScreen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/analysis_metrics.dart';
import 'package:ride_metric_x/models/recommendation.dart';
import 'package:ride_metric_x/models/suspension_parameters.dart';
import 'package:ride_metric_x/models/telemetry_series.dart';
import 'package:ride_metric_x/screens/analysis_screen.dart';
import 'package:ride_metric_x/services/recommendation_engine.dart';
import 'package:ride_metric_x/widgets/recommendation_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _suggested = TuningParameters.firmPreset;

Recommendation _makeRec({
  String id = 'test_rec',
  RecommendationType type = RecommendationType.bottomingTooMuch,
  RecommendationSeverity severity = RecommendationSeverity.high,
  String title = 'Test recommendation title',
  String rationale = 'Detailed rationale text.',
  TuningParameters? suggestedParameters = _suggested,
}) {
  return Recommendation(
    id: id,
    type: type,
    severity: severity,
    title: title,
    rationale: rationale,
    suggestedParameters: suggestedParameters,
  );
}

// ── RecommendationCard tests ──────────────────────────────────────────────────

void main() {
  group('RecommendationCard rendering', () {
    testWidgets('shows title text', (tester) async {
      await tester.pumpWidget(
        _wrap(RecommendationCard(recommendation: _makeRec())),
      );

      expect(find.text('Test recommendation title'), findsOneWidget);
    });

    testWidgets('shows HIGH severity badge label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecommendationCard(
            recommendation: _makeRec(severity: RecommendationSeverity.high),
          ),
        ),
      );

      expect(find.text('HIGH'), findsOneWidget);
    });

    testWidgets('shows MED severity badge label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecommendationCard(
            recommendation: _makeRec(severity: RecommendationSeverity.medium),
          ),
        ),
      );

      expect(find.text('MED'), findsOneWidget);
    });

    testWidgets('shows LOW severity badge label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecommendationCard(
            recommendation: _makeRec(severity: RecommendationSeverity.low),
          ),
        ),
      );

      expect(find.text('LOW'), findsOneWidget);
    });

    testWidgets('rationale text is hidden initially', (tester) async {
      final rec = _makeRec(id: 'r1');
      await tester.pumpWidget(_wrap(RecommendationCard(recommendation: rec)));

      expect(
        find.byKey(RecommendationCard.rationaleKey('r1')),
        findsNothing,
      );
    });

    testWidgets('tapping card header reveals rationale text', (tester) async {
      final rec = _makeRec(id: 'r2', rationale: 'Detailed rationale text.');
      await tester.pumpWidget(_wrap(RecommendationCard(recommendation: rec)));

      await tester.tap(find.text(rec.title));
      await tester.pump();

      expect(
        find.byKey(RecommendationCard.rationaleKey('r2')),
        findsOneWidget,
      );
      expect(find.text('Detailed rationale text.'), findsOneWidget);
    });

    testWidgets('tapping card again collapses rationale', (tester) async {
      final rec = _makeRec(id: 'r3');
      await tester.pumpWidget(_wrap(RecommendationCard(recommendation: rec)));

      await tester.tap(find.text(rec.title));
      await tester.pump();
      await tester.tap(find.text(rec.title));
      await tester.pump();

      expect(
        find.byKey(RecommendationCard.rationaleKey('r3')),
        findsNothing,
      );
    });

    testWidgets('apply button is visible when suggestedParameters is set',
        (tester) async {
      final rec = _makeRec(id: 'r4', suggestedParameters: _suggested);
      await tester.pumpWidget(_wrap(RecommendationCard(recommendation: rec)));

      // Expand the card first.
      await tester.tap(find.text(rec.title));
      await tester.pump();

      expect(find.byKey(RecommendationCard.applyKey('r4')), findsOneWidget);
      expect(find.text('Apply Suggestion'), findsOneWidget);
    });

    testWidgets('apply button is absent when suggestedParameters is null',
        (tester) async {
      final rec = _makeRec(id: 'r5', suggestedParameters: null);
      await tester.pumpWidget(_wrap(RecommendationCard(recommendation: rec)));

      await tester.tap(find.text(rec.title));
      await tester.pump();

      expect(find.byKey(RecommendationCard.applyKey('r5')), findsNothing);
      expect(find.text('Apply Suggestion'), findsNothing);
    });

    testWidgets('tapping apply button calls onApply with suggestedParameters',
        (tester) async {
      TuningParameters? applied;
      final rec = _makeRec(id: 'r6', suggestedParameters: _suggested);

      await tester.pumpWidget(
        _wrap(
          RecommendationCard(
            recommendation: rec,
            onApply: (p) => applied = p,
          ),
        ),
      );

      // Expand the card.
      await tester.tap(find.text(rec.title));
      await tester.pump();

      // Tap apply.
      await tester.tap(find.byKey(RecommendationCard.applyKey('r6')));
      await tester.pump();

      expect(applied, equals(_suggested));
    });

    testWidgets('apply button does nothing when onApply is null',
        (tester) async {
      final rec = _makeRec(id: 'r7', suggestedParameters: _suggested);
      await tester.pumpWidget(
        _wrap(RecommendationCard(recommendation: rec)),
      );

      await tester.tap(find.text(rec.title));
      await tester.pump();

      // Tapping should not throw.
      await tester.tap(find.byKey(RecommendationCard.applyKey('r7')));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // ── RecommendationsPanel tests ────────────────────────────────────────────────

  group('RecommendationsPanel rendering', () {
    testWidgets('shows panel key', (tester) async {
      await tester.pumpWidget(
        _wrap(const RecommendationsPanel(recommendations: [])),
      );

      expect(find.byKey(RecommendationsPanel.panelKey), findsOneWidget);
    });

    testWidgets('shows "no issues" message when recommendations is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const RecommendationsPanel(recommendations: [])),
      );

      expect(
        find.byKey(RecommendationsPanel.noIssuesKey),
        findsOneWidget,
      );
    });

    testWidgets('does not show "no issues" when recommendations are present',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecommendationsPanel(
            recommendations: [_makeRec()],
          ),
        ),
      );

      expect(find.byKey(RecommendationsPanel.noIssuesKey), findsNothing);
    });

    testWidgets('renders a card for each recommendation', (tester) async {
      final recs = [
        _makeRec(id: 'a', title: 'First rec'),
        _makeRec(id: 'b', title: 'Second rec'),
        _makeRec(id: 'c', title: 'Third rec'),
      ];

      await tester.pumpWidget(
        _wrap(SingleChildScrollView(child: RecommendationsPanel(recommendations: recs))),
      );

      expect(find.text('First rec'), findsOneWidget);
      expect(find.text('Second rec'), findsOneWidget);
      expect(find.text('Third rec'), findsOneWidget);
    });

    testWidgets('header shows "Recommendations" title', (tester) async {
      await tester.pumpWidget(
        _wrap(const RecommendationsPanel(recommendations: [])),
      );

      expect(find.text('Recommendations'), findsOneWidget);
    });

    testWidgets('forwards onApply to card', (tester) async {
      TuningParameters? applied;
      final rec = _makeRec(id: 'fwd', suggestedParameters: _suggested);

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: RecommendationsPanel(
              recommendations: [rec],
              onApply: (p) => applied = p,
            ),
          ),
        ),
      );

      // Expand the card.
      await tester.tap(find.text(rec.title));
      await tester.pump();

      // Tap apply.
      await tester.tap(find.byKey(RecommendationCard.applyKey('fwd')));
      await tester.pump();

      expect(applied, equals(_suggested));
    });
  });

  // ── AnalysisScreen integration ────────────────────────────────────────────────

  group('AnalysisScreen with recommendations', () {
    const singleTab = ChartTab(
      title: 'Accel',
      xLabel: 'ms',
      yLabel: 'g',
      series: [
        TelemetrySeries(
          label: 'Front Z',
          color: Colors.blue,
          points: [Offset(0, 1), Offset(1, 2)],
        ),
      ],
    );

    testWidgets(
        'shows RecommendationsPanel when recommendations list is provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisScreen(
              tabs: const [singleTab],
              recommendations: [_makeRec()],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(RecommendationsPanel.panelKey), findsOneWidget);
    });

    testWidgets(
        'does not show RecommendationsPanel when recommendations is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnalysisScreen(tabs: [singleTab]),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(RecommendationsPanel.panelKey), findsNothing);
    });

    testWidgets('shows empty recommendations panel with no-issues text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnalysisScreen(
              tabs: [singleTab],
              recommendations: [],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(RecommendationsPanel.noIssuesKey), findsOneWidget);
    });

    testWidgets(
        'apply action propagates via onApplyRecommendation callback',
        (tester) async {
      TuningParameters? applied;
      final rec = _makeRec(id: 'int1', suggestedParameters: _suggested);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisScreen(
              tabs: const [singleTab],
              recommendations: [rec],
              onApplyRecommendation: (p) => applied = p,
            ),
          ),
        ),
      );
      await tester.pump();

      // Expand the recommendation card.
      await tester.tap(find.text(rec.title));
      await tester.pump();

      // Tap Apply Suggestion.
      await tester.tap(find.byKey(RecommendationCard.applyKey('int1')));
      await tester.pump();

      expect(applied, equals(_suggested));
    });
  });

  // ── Integration: engine → panel → apply ──────────────────────────────────────

  group('End-to-end: RecommendationEngine → RecommendationsPanel → apply', () {
    testWidgets(
        'generated HIGH bottoming recommendation appears and can be applied',
        (tester) async {
      const engine = RecommendationEngine();
      const metrics = AnalysisMetrics(rearBottomingEvents: 12); // HIGH
      final recs = engine.generate(metrics, TuningParameters.defaultPreset);

      TuningParameters? applied;

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: RecommendationsPanel(
              recommendations: recs,
              onApply: (p) => applied = p,
            ),
          ),
        ),
      );

      // HIGH badge should appear.
      expect(find.text('HIGH'), findsOneWidget);

      // Tap the card to expand it.
      final cardFinder = find.byKey(const ValueKey('rec_card_bottoming'));
      await tester.tap(cardFinder);
      await tester.pump();

      // Apply Suggestion button.
      await tester.tap(
        find.byKey(RecommendationCard.applyKey('bottoming')),
      );
      await tester.pump();

      // Callback was called and rear compression was increased.
      expect(applied, isNotNull);
      expect(
        applied!.rear.compression,
        greaterThan(TuningParameters.defaultPreset.rear.compression),
      );
    });

    testWidgets('nominal metrics produce no-issues panel', (tester) async {
      const engine = RecommendationEngine();
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 80.0,
        rearTravelUsagePercent: 80.0,
      );
      final recs = engine.generate(metrics, TuningParameters.defaultPreset);

      await tester.pumpWidget(
        _wrap(
          RecommendationsPanel(recommendations: recs),
        ),
      );

      expect(find.byKey(RecommendationsPanel.noIssuesKey), findsOneWidget);
    });
  });
}
