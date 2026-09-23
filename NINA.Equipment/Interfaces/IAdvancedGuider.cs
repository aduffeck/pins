#region "copyright"

/*
    Copyright (c) 2026 André Duffeck and the PINS contributors

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace NINA.Equipment.Interfaces {

    /// <summary>
    /// Optional extension of <see cref="IGuider"/> for guiders that run inside PINS (e.g. the native guider plugin)
    /// and can expose rich live data to UIs: frames with star overlays, per-frame guide steps, calibration,
    /// statistics, alerts and editable settings. UIs discover it with <c>guiderMediator.GetDevice() as IAdvancedGuider</c>.
    /// All DTOs are plain, JSON-serializable classes. Implementations must be thread-safe.
    /// </summary>
    public interface IAdvancedGuider : IGuider {

        /// <summary>Snapshot of the guider state, current star, calibration progress, statistics and last error.</summary>
        AdvancedGuiderStatus GetStatus();

        /// <summary>Most recent guide steps (oldest first), at most <paramref name="maxCount"/>.</summary>
        IReadOnlyList<AdvancedGuideStep> GetRecentSteps(int maxCount);

        /// <summary>Most recent alerts/events (oldest first), at most <paramref name="maxCount"/>.</summary>
        IReadOnlyList<AdvancedGuiderAlert> GetRecentAlerts(int maxCount);

        /// <summary>Latest processed guide frame with star overlays, or null when no frame was taken yet.</summary>
        AdvancedGuiderFrame GetLatestFrame();

        /// <summary>Current calibration, or null when not calibrated.</summary>
        AdvancedGuiderCalibration GetCalibration();

        /// <summary>All settings with metadata for building a settings form.</summary>
        IReadOnlyList<AdvancedGuiderSetting> GetSettings();

        /// <summary>Change a setting by name (value as invariant-culture string). Returns false with an error message when rejected.</summary>
        bool TrySetSetting(string name, string value, out string error);

        /// <summary>Guide camera devices available for the configured guide camera driver.</summary>
        Task<IReadOnlyList<string>> GetAvailableGuideCameras(CancellationToken ct);

        /// <summary>Start looping exposures without guiding (for framing/focusing the guide camera).</summary>
        Task<bool> StartLooping(CancellationToken ct);

        /// <summary>Stop looping/guiding and stop exposures.</summary>
        Task<bool> StopLooping(CancellationToken ct);

        /// <summary>Pause or resume guiding (exposures continue while paused).</summary>
        Task<bool> SetPaused(bool paused, CancellationToken ct);

        /// <summary>Dither by up to <paramref name="pixels"/> guide pixels and wait for settling.</summary>
        Task<bool> DitherBy(double pixels, bool raOnly, CancellationToken ct);

        /// <summary>
        /// Build a dark library for exposures between <paramref name="minExposureSeconds"/> and <paramref name="maxExposureSeconds"/>
        /// (PHD2's standard exposure steps), <paramref name="framesPerExposure"/> frames each. The guide scope must be covered and
        /// the guider stopped. Progress is reported through <see cref="AdvancedGuiderEvent"/> with type "darks".
        /// </summary>
        Task<bool> BuildDarkLibrary(double minExposureSeconds, double maxExposureSeconds, int framesPerExposure, CancellationToken ct);

        /// <summary>Raised for every guide step, alert, state change, calibration step, settle update and new frame.</summary>
        event EventHandler<AdvancedGuiderEventArgs> AdvancedGuiderEvent;
    }

    /// <summary>Event pushed to UIs. <see cref="Type"/> is one of: step, alert, state, calibration, settle, frame, stats.</summary>
    public class AdvancedGuiderEventArgs : EventArgs {
        public string Type { get; set; }
        public DateTime Timestamp { get; set; }

        /// <summary>One of the DTOs of this file (AdvancedGuideStep, AdvancedGuiderAlert, AdvancedGuiderStatus, ...), or a small anonymous object for frame notifications.</summary>
        public object Payload { get; set; }
    }

    public class AdvancedGuiderStatus {
        /// <summary>Stopped, Looping, Selected, Calibrating, Guiding, LostLock, Reacquiring, Paused, Failed.</summary>
        public string State { get; set; }
        public bool Connected { get; set; }
        public bool IsSettling { get; set; }
        public bool IsCalibrated { get; set; }
        public string CameraName { get; set; }
        public double ExposureSeconds { get; set; }
        public double PixelScale { get; set; }
        public long FrameNumber { get; set; }
        public double LastProcessingMs { get; set; }
        public double? LockX { get; set; }
        public double? LockY { get; set; }
        public AdvancedGuideStar PrimaryStar { get; set; }
        public int StarsUsed { get; set; }
        public int StarCount { get; set; }
        public string CalibrationStep { get; set; }
        public double CalibrationProgress { get; set; }
        public AdvancedGuiderStats WindowStats { get; set; }
        public AdvancedGuiderStats SessionStats { get; set; }
        public AdvancedGuiderAlert LastError { get; set; }
        public string SettleStatus { get; set; }

        /// <summary>Dark library in use (file name and number of darks), empty when none.</summary>
        public string DarkLibrary { get; set; }
    }

    public class AdvancedGuiderStats {
        public int Frames { get; set; }
        public double RmsRaArcsec { get; set; }
        public double RmsDecArcsec { get; set; }
        public double RmsTotalArcsec { get; set; }
        public double RmsRaPx { get; set; }
        public double RmsDecPx { get; set; }
        public double RmsTotalPx { get; set; }
        public double PeakRaArcsec { get; set; }
        public double PeakDecArcsec { get; set; }
        public double? DriftRaArcsecPerMin { get; set; }
        public double? DriftDecArcsecPerMin { get; set; }
        public double? PolarAlignmentErrorArcmin { get; set; }
        public double OscillationIndex { get; set; }
        public double RaDutyPercent { get; set; }
        public double DecDutyPercent { get; set; }
        public double? SnrMin { get; set; }
        public double? SnrAvg { get; set; }
        public double? SnrLast { get; set; }
        public double? AvgStarCount { get; set; }
        public int StarLostCount { get; set; }
        public double ElapsedSeconds { get; set; }
    }

    public class AdvancedGuideStep {
        public long Frame { get; set; }
        public DateTime Timestamp { get; set; }

        /// <summary>Seconds since guiding started.</summary>
        public double Time { get; set; }
        public double Dx { get; set; }
        public double Dy { get; set; }

        /// <summary>Mount-axis error in guide pixels.</summary>
        public double RaDistanceRaw { get; set; }
        public double DecDistanceRaw { get; set; }

        /// <summary>Mount-axis error in arcsec.</summary>
        public double RaArcsec { get; set; }
        public double DecArcsec { get; set; }
        public int RaDuration { get; set; }

        /// <summary>East/West or empty.</summary>
        public string RaDirection { get; set; }
        public int DecDuration { get; set; }

        /// <summary>North/South or empty.</summary>
        public string DecDirection { get; set; }
        public bool RaLimited { get; set; }
        public bool DecLimited { get; set; }
        public double Snr { get; set; }
        public double StarMass { get; set; }
        public double Hfd { get; set; }
        public int StarsUsed { get; set; }
        public bool IsSettling { get; set; }
        public bool IsRecenterMove { get; set; }
        public bool PrimaryEstimated { get; set; }
        public double AvgDist { get; set; }
    }

    public class AdvancedGuiderAlert {
        public DateTime Timestamp { get; set; }
        public int Code { get; set; }
        public string CodeName { get; set; }

        /// <summary>Info, Warning or Critical.</summary>
        public string Severity { get; set; }
        public string Title { get; set; }
        public string Explanation { get; set; }
        public string Fix { get; set; }
        public string Detail { get; set; }
    }

    public class AdvancedGuideStar {
        public double X { get; set; }
        public double Y { get; set; }
        public double Snr { get; set; }
        public double Mass { get; set; }
        public double Hfd { get; set; }
        public bool IsPrimary { get; set; }
        public bool Used { get; set; }
        public double Weight { get; set; }

        /// <summary>Why the star was not used this frame (Miss, Lost, NotMeasured, ...), null when used.</summary>
        public string RejectReason { get; set; }
    }

    public class AdvancedGuiderFrame {
        public long FrameNumber { get; set; }
        public DateTime Timestamp { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int BitDepth { get; set; }

        /// <summary>Row-major 16-bit pixels (after dark/defect correction).</summary>
        public ushort[] Pixels { get; set; }
        public double? LockX { get; set; }
        public double? LockY { get; set; }
        public List<AdvancedGuideStar> Stars { get; set; } = new List<AdvancedGuideStar>();
    }

    public class AdvancedGuiderCalibration {
        public DateTime Timestamp { get; set; }

        /// <summary>Camera angle of the RA axis (direction a star moves for an East pulse), degrees.</summary>
        public double RaAngleDeg { get; set; }

        /// <summary>Camera angle of the Dec axis (direction a star moves for a North pulse), degrees.</summary>
        public double DecAngleDeg { get; set; }
        public double RaRatePxPerSec { get; set; }
        public double DecRatePxPerSec { get; set; }
        public double RaRateArcsecPerSec { get; set; }
        public double DecRateArcsecPerSec { get; set; }
        public double OrthogonalityErrorDeg { get; set; }
        public double? DeclinationDeg { get; set; }
        public string PierSide { get; set; }
        public int Binning { get; set; }
        public int RaSteps { get; set; }
        public int DecSteps { get; set; }
        public string LastIssue { get; set; }
        public bool DecFlipRequired { get; set; }
    }

    public class AdvancedGuiderSetting {
        public string Name { get; set; }
        public string Label { get; set; }
        public string Group { get; set; }
        public string Description { get; set; }

        /// <summary>int, double, bool, string or enum.</summary>
        public string Type { get; set; }

        /// <summary>Current value as invariant-culture string.</summary>
        public string Value { get; set; }
        public string DefaultValue { get; set; }
        public double? Min { get; set; }
        public double? Max { get; set; }
        public string Unit { get; set; }

        /// <summary>Allowed values for enum settings.</summary>
        public List<string> Options { get; set; }

        /// <summary>True when the value is only applied on the next connect.</summary>
        public bool RequiresReconnect { get; set; }

        /// <summary>True for the essential settings shown in the basic settings view.</summary>
        public bool Basic { get; set; }
    }
}
