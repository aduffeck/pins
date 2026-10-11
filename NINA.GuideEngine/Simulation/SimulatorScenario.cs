// SPDX-License-Identifier: MPL-2.0

namespace NINA.GuideEngine.Simulation;

/// <summary>Complete, immutable simulator configuration. Use <c>with</c> to derive variants.</summary>
public sealed record SimulatorScenario
{
    public string Name { get; init; } = "Default";

    public MountSimConfig Mount { get; init; } = new();

    public SkySimConfig Sky { get; init; } = new();

    public CameraSimConfig Camera { get; init; } = new();

    /// <summary>A well-behaved mount: small PE, slight polar misalignment, average seeing.</summary>
    public static SimulatorScenario GoodMount { get; } = new()
    {
        Name = nameof(GoodMount),
        Mount = new MountSimConfig
        {
            PeriodicError = [new PeriodicErrorTerm(2.0, 480.0), new PeriodicErrorTerm(0.5, 240.0, 1.0)],
            DecDriftArcsecPerMin = 0.3,
            RaDriftArcsecPerMin = 0.1,
            RandomWalkArcsecPerSqrtSec = 0.02,
        },
        Sky = new SkySimConfig { SeeingJitterArcsec = 0.3 },
    };

    /// <summary>Large periodic error with harmonics (cheap mount, no PEC).</summary>
    public static SimulatorScenario PoorPeriodicError { get; } = GoodMount with
    {
        Name = nameof(PoorPeriodicError),
        Mount = GoodMount.Mount with
        {
            PeriodicError =
            [
                new PeriodicErrorTerm(15.0, 480.0),
                new PeriodicErrorTerm(5.0, 240.0, 0.7),
                new PeriodicErrorTerm(2.0, 160.0, 2.1),
            ],
        },
    };

    /// <summary>Poor seeing: large image motion and bloated stars.</summary>
    public static SimulatorScenario HighSeeing { get; } = GoodMount with
    {
        Name = nameof(HighSeeing),
        Sky = GoodMount.Sky with { SeeingJitterArcsec = 1.5, FwhmArcsec = 5.5, SeeingCommonFraction = 0.3 },
    };

    /// <summary>Significant Dec backlash plus a Dec drift that forces reversals.</summary>
    public static SimulatorScenario Backlash { get; } = GoodMount with
    {
        Name = nameof(Backlash),
        Mount = GoodMount.Mount with { DecBacklashArcsec = 12.0, DecDriftArcsecPerMin = 1.0 },
    };

    /// <summary>Passing clouds: dimming, then a total loss of the stars for a while.</summary>
    public static SimulatorScenario Clouds { get; } = GoodMount with
    {
        Name = nameof(Clouds),
        Sky = GoodMount.Sky with
        {
            Transparency =
            [
                new TransparencyWindow(60.0, 120.0, 0.3, 10.0),
                new TransparencyWindow(200.0, 240.0, 0.0, 5.0),
                new TransparencyWindow(300.0, 330.0, 0.6, 5.0),
            ],
        },
    };

    /// <summary>Warm, uncooled sensor with many hot and cold pixels.</summary>
    public static SimulatorScenario HotPixelHeavy { get; } = GoodMount with
    {
        Name = nameof(HotPixelHeavy),
        Camera = GoodMount.Camera with { HotPixelCount = 600, ColdPixelCount = 150, DarkCurrentElectronsPerSec = 2.0 },
    };

    /// <summary>
    /// A typical strain-wave (harmonic drive) mount, AM5 or NYX-101 class: ±18″ at 430.8 s (twice per turn of a wave
    /// generator of 861.6 s) with two harmonics, a curve that changes over a few cycles, short components at 2.9 s and
    /// 62 s, guide rate 0.9×, no Dec backlash. Variant B of docs/notes/SHORT-EXPOSURES.md §4.1; the spreads of amplitude
    /// and phase are guesses, since nobody has published them.
    /// </summary>
    public static SimulatorScenario HarmonicDrive { get; } = HarmonicDriveBase(nameof(HarmonicDrive), 430.8,
        amplitudeChange: 0.18, amplitudeCycles: 10, phaseChangeDeg: 10, phaseCycles: 2,
        [
            new PeriodicErrorTerm(18.0, 430.8),
            new PeriodicErrorTerm(2.0, 215.4, 1.3),
            new PeriodicErrorTerm(2.0, 143.6, 2.6),
        ],
        [new PeriodicErrorTerm(0.2, 2.9, 0.4), new PeriodicErrorTerm(0.3, 62.0, 1.9)]);

    /// <summary>
    /// A modern belt-driven strain-wave mount, AM5N, AM7 or Wave class: ±7″ at 287.2 s (the motor pulley) and ±3″ at
    /// 430.8 s, a ratio of 1.5 that only the common 861.6 s holds; amplitude ±10 % over ten cycles. Variant A of §4.1.
    /// </summary>
    public static SimulatorScenario HarmonicDriveModern { get; } = HarmonicDriveBase(nameof(HarmonicDriveModern), 287.2,
        amplitudeChange: 0.10, amplitudeCycles: 10, phaseChangeDeg: 0, phaseCycles: 0,
        [new PeriodicErrorTerm(7.0, 287.2), new PeriodicErrorTerm(3.0, 430.8, 1.1)],
        [new PeriodicErrorTerm(0.2, 2.9, 0.4)]);

    /// <summary>
    /// A rough strain-wave mount, RST-135 or HEM class: ±25″ at 430.8 s with strong harmonics, amplitude ±30 % and phase
    /// ±30° from one cycle to the next, ±1.5″ at 2.4 s (from a forum report only) and ±0.3″ at 9.2 s, 4″ of Dec backlash
    /// (a belt) and wind gusts (no counterweight). Variant C of §4.1.
    /// </summary>
    public static SimulatorScenario HarmonicDriveRough { get; } = HarmonicDriveBase(nameof(HarmonicDriveRough), 430.8,
        amplitudeChange: 0.30, amplitudeCycles: 1, phaseChangeDeg: 30, phaseCycles: 1,
        [
            new PeriodicErrorTerm(25.0, 430.8),
            new PeriodicErrorTerm(8.0, 215.4, 1.3),
            new PeriodicErrorTerm(3.0, 143.6, 2.6),
        ],
        [new PeriodicErrorTerm(1.5, 2.4, 0.4), new PeriodicErrorTerm(0.3, 9.2, 2.2)],
        decBacklashArcsec: 4.0, wind: new WindGustConfig(1.0, 2.0, 3.0));

    /// <summary>All presets, for parameterised tests.</summary>
    public static IReadOnlyList<SimulatorScenario> Presets { get; } =
        [GoodMount, PoorPeriodicError, HighSeeing, Backlash, Clouds, HotPixelHeavy, HarmonicDrive];

    public override string ToString() => Name;

    // what the three strain-wave variants share: GoodMount's sky, camera, drifts and random walk, the curve on the RA axis
    // angle, guide rates 0.9×; the main lines change along the gear (in cycles of the dominant period), the short
    // components don't
    private static SimulatorScenario HarmonicDriveBase(
        string name,
        double dominantPeriodSec,
        double amplitudeChange,
        double amplitudeCycles,
        double phaseChangeDeg,
        double phaseCycles,
        IReadOnlyList<PeriodicErrorTerm> mainLines,
        IReadOnlyList<PeriodicErrorTerm> shortComponents,
        double decBacklashArcsec = 0,
        WindGustConfig? wind = null) => GoodMount with
    {
        Name = name,
        Mount = GoodMount.Mount with
        {
            PeriodicError =
            [
                .. mainLines.Select(t => t with
                {
                    AmplitudeChange = amplitudeChange,
                    AmplitudeChangeSec = amplitudeCycles * dominantPeriodSec,
                    PhaseChangeRad = phaseChangeDeg * Math.PI / 180,
                    PhaseChangeSec = phaseCycles * dominantPeriodSec,
                }),
                .. shortComponents,
            ],
            PeriodicErrorFollowsAxis = true,
            GuideRateRa = 0.9,
            GuideRateDec = 0.9,
            DecBacklashArcsec = decBacklashArcsec,
            Wind = wind,
        },
    };
}
