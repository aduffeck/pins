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

    /// <summary>All presets, for parameterised tests.</summary>
    public static IReadOnlyList<SimulatorScenario> Presets { get; } =
        [GoodMount, PoorPeriodicError, HighSeeing, Backlash, Clouds, HotPixelHeavy];

    public override string ToString() => Name;
}
