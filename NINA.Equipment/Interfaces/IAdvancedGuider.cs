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

        /// <summary>
        /// Start a Guiding Coach session (see docs/COACH.md of pins-guider): camera check (exposure × gain), sky and mount
        /// drift with guiding output off, mount response (Dec backlash, pulse response), guided trials of settings sets and a
        /// report card. Returns once the session was accepted (it runs in the background) or rejected; a rejection is reported
        /// only in the result and leaves the status of a running/last session untouched. Stops guiding/looping as needed; guiding that
        /// was active at the start is resumed with the original settings when the session ends (also after cancel).
        /// Progress via <see cref="AdvancedGuiderEvent"/> type "coach" (payload <see cref="AdvancedCoachStatus"/>).
        /// </summary>
        Task<AdvancedCoachStartResult> StartCoach(AdvancedCoachOptions options, CancellationToken ct);

        /// <summary>Skip the running step (its partial results are kept when usable).</summary>
        Task<bool> SkipCoachStep(CancellationToken ct);

        /// <summary>Cancel the session; temporary settings are restored and guiding output re-enabled.</summary>
        Task<bool> CancelCoach(CancellationToken ct);

        /// <summary>Current or last session (Phase Idle before the first session); always carries the camera's gain range.</summary>
        AdvancedCoachStatus GetCoachStatus();

        /// <summary>
        /// Apply the setting changes of the given findings (<see cref="AdvancedCoachFinding.Id"/>) or trials ("trial:&lt;id&gt;")
        /// of the current/last session, or of active live hints (a hint applied this way is dismissed), to the guider settings.
        /// </summary>
        Task<bool> ApplyCoachActions(IList<string> ids, CancellationToken ct);

        /// <summary>Stored reports of the active profile, newest first, without the raw samples.</summary>
        IList<AdvancedCoachReport> GetCoachHistory(int max);

        /// <summary>Hide a live hint (<see cref="AdvancedCoachFinding.Id"/>) for the rest of the guiding session.</summary>
        bool DismissHint(string id);

        /// <summary>Raised for every guide step, alert, state change, calibration step, settle update and new frame.</summary>
        event EventHandler<AdvancedGuiderEventArgs> AdvancedGuiderEvent;
    }

    /// <summary>Event pushed to UIs. <see cref="Type"/> is one of: step, alert, state, calibration, settle, frame, stats, darks, coach, hint.</summary>
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

        /// <summary>Active (not expired, not dismissed) live coaching hints while guiding.</summary>
        public List<AdvancedCoachFinding> Hints { get; set; } = new List<AdvancedCoachFinding>();

        /// <summary>True while a Guiding Coach session is running (guiding commands are refused or cancel it).</summary>
        public bool CoachRunning { get; set; }
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

        /// <summary>Star position after every calibration step (camera px), empty for older calibrations.</summary>
        public List<AdvancedCalibrationPoint> Points { get; set; } = new List<AdvancedCalibrationPoint>();
    }

    public class AdvancedCalibrationPoint {
        /// <summary>Start, West, East, Backlash, North, South or NudgeSouth.</summary>
        public string Direction { get; set; }
        public int Step { get; set; }
        public double X { get; set; }
        public double Y { get; set; }
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

    public class AdvancedCoachOptions {
        /// <summary>Steps to run: CameraCheck, Drift, MountResponse, Trials (the report is always built). Empty = all.</summary>
        public List<string> Steps { get; set; } = new List<string>();

        /// <summary>Camera check exposures; empty = 1, 2, 3 s.</summary>
        public List<double> ExposureSeconds { get; set; } = new List<double>();

        /// <summary>Camera check gains; empty = current gain plus two spread over the camera's gain range (current only without a range).</summary>
        public List<int> Gains { get; set; } = new List<int>();
        public int FramesPerCombination { get; set; } = 5;
        public double DriftSeconds { get; set; } = 180;
        public double TrialSeconds { get; set; } = 120;

        /// <summary>Guide with the current settings again at the end of the trials to detect changing conditions.</summary>
        public bool RepeatBaseline { get; set; } = true;

        /// <summary>Calibrate when a step needs a calibration and none is valid (otherwise such steps fail).</summary>
        public bool AllowCalibration { get; set; } = true;
    }

    public class AdvancedCoachStatus {
        /// <summary>Idle, Running, Complete, Cancelled or Failed.</summary>
        public string Phase { get; set; }

        /// <summary>Failure/rejection reason (English), null otherwise.</summary>
        public string Message { get; set; }

        /// <summary>Stable code of <see cref="Message"/> for localisation (e.g. coach.interrupted, coach.calibrationFailed).</summary>
        public string MessageCode { get; set; }

        /// <summary>Parameters of <see cref="MessageCode"/> (e.g. { "reason": "slew" }).</summary>
        public Dictionary<string, object> MessageParameters { get; set; } = new Dictionary<string, object>();
        public string SessionId { get; set; }
        public DateTime? StartedAt { get; set; }

        /// <summary>Running step: CameraCheck, Calibrating, Drift, MountResponse, Trials or Report; null when not running.</summary>
        public string Step { get; set; }
        public List<AdvancedCoachStepStatus> Steps { get; set; } = new List<AdvancedCoachStepStatus>();

        /// <summary>Overall progress 0..1.</summary>
        public double Progress { get; set; }
        public double ElapsedSeconds { get; set; }
        public double EstimatedTotalSeconds { get; set; }

        /// <summary>Camera gain range and current settings (also when idle, for building the options).</summary>
        public int? GainMin { get; set; }
        public int? GainMax { get; set; }
        public int? CurrentGain { get; set; }
        public double CurrentExposureSeconds { get; set; }
        public AdvancedCoachCameraCheck Camera { get; set; }
        public AdvancedCoachDrift Drift { get; set; }
        public AdvancedCoachResponse Response { get; set; }
        public List<AdvancedCoachTrial> Trials { get; set; } = new List<AdvancedCoachTrial>();

        /// <summary>Findings so far (all steps).</summary>
        public List<AdvancedCoachFinding> Findings { get; set; } = new List<AdvancedCoachFinding>();

        /// <summary>Set when the session completed.</summary>
        public AdvancedCoachReport Report { get; set; }
    }

    public class AdvancedCoachStepStatus {
        /// <summary>CameraCheck, Drift, MountResponse or Trials.</summary>
        public string Name { get; set; }

        /// <summary>Pending, Running, Done, Skipped or Failed.</summary>
        public string State { get; set; }

        /// <summary>English sub-phase text (logs); UIs render <see cref="DetailCode"/>.</summary>
        public string Detail { get; set; }

        /// <summary>
        /// Sub-phase code: camera.combination {exposureSeconds, gain, index, total}, calibrating, drift.measuring,
        /// response.backlash, response.pulses {direction, ms}, trial.settling {id}, trial.running {id}; null when none.
        /// </summary>
        public string DetailCode { get; set; }
        public Dictionary<string, object> DetailParameters { get; set; } = new Dictionary<string, object>();

        /// <summary>0..1.</summary>
        public double Progress { get; set; }
        public double ElapsedSeconds { get; set; }
        public double EstimatedSeconds { get; set; }

        /// <summary>Why the step failed (English) and its code, null otherwise.</summary>
        public string Message { get; set; }
        public string MessageCode { get; set; }
        public Dictionary<string, object> MessageParameters { get; set; } = new Dictionary<string, object>();
    }

    public class AdvancedCoachStartResult {
        public bool Accepted { get; set; }

        /// <summary>Rejection reason (English), its code (coach.busy, coach.notConnected, ...) and parameters; null when accepted.</summary>
        public string Message { get; set; }
        public string MessageCode { get; set; }
        public Dictionary<string, object> MessageParameters { get; set; } = new Dictionary<string, object>();

        /// <summary>Status after the call (the new session when accepted, the unchanged status when rejected).</summary>
        public AdvancedCoachStatus Status { get; set; }
    }

    public class AdvancedCoachCameraCheck {
        public List<AdvancedCoachCameraResult> Results { get; set; } = new List<AdvancedCoachCameraResult>();
        public AdvancedCoachCameraResult Recommended { get; set; }
    }

    public class AdvancedCoachCameraResult {
        public double ExposureSeconds { get; set; }
        public int Gain { get; set; }
        public int Frames { get; set; }
        public double? Snr { get; set; }
        public double? Hfd { get; set; }
        public int Stars { get; set; }
        public bool Saturated { get; set; }

        /// <summary>Centroid scatter of the primary star (guiding off, linear drift removed).</summary>
        public double? JitterPx { get; set; }
        public double? JitterArcsec { get; set; }
        public bool Feasible { get; set; }

        /// <summary>Why the combination is not feasible: saturated, lowSnr, noStar; null when feasible.</summary>
        public string Reason { get; set; }
    }

    public class AdvancedCoachSample {
        /// <summary>Seconds since the measurement started.</summary>
        public double T { get; set; }

        /// <summary>Mount-axis position relative to the start, arcsec.</summary>
        public double Ra { get; set; }
        public double Dec { get; set; }
    }

    public class AdvancedCoachDrift {
        public double ElapsedSeconds { get; set; }
        public double TargetSeconds { get; set; }

        /// <summary>Raw samples (live plot); omitted in the history.</summary>
        public List<AdvancedCoachSample> Samples { get; set; } = new List<AdvancedCoachSample>();
        public double? SnrAvg { get; set; }

        /// <summary>High-frequency (seeing) RMS with guiding off.</summary>
        public double? SeeingRaArcsec { get; set; }
        public double? SeeingDecArcsec { get; set; }
        public double? SeeingTotalArcsec { get; set; }
        public double? RaPeakToPeakArcsec { get; set; }
        public double? RaMaxRateArcsecPerSec { get; set; }
        public double? RaDriftArcsecPerMin { get; set; }
        public double? DecDriftArcsecPerMin { get; set; }

        /// <summary>
        /// Periodic error fit (null when the run is too short for a period). Model on the RA samples:
        /// Ra(T) = PeriodicErrorOffsetArcsec + RaDriftArcsecPerMin * T / 60 + PeriodicErrorAmplitudeArcsec * sin(2π T / PeriodicErrorPeriodSeconds + PeriodicErrorPhaseRad),
        /// T = <see cref="AdvancedCoachSample.T"/>.
        /// </summary>
        public double? PeriodicErrorPeriodSeconds { get; set; }

        /// <summary>Amplitude (half peak-to-peak) of the fitted sinusoid, arcsec.</summary>
        public double? PeriodicErrorAmplitudeArcsec { get; set; }
        public double? PeriodicErrorPhaseRad { get; set; }
        public double? PeriodicErrorOffsetArcsec { get; set; }
        public double? PolarAlignmentErrorArcmin { get; set; }

        /// <summary>True when the declination was unknown and 0° was assumed.</summary>
        public bool DeclinationAssumed { get; set; }
        public double? DriftLimitingExposureSeconds { get; set; }

        /// <summary>Share of frame-to-frame jumps larger than 4 σ of the high-frequency jitter (wind, gusts), 0..100.</summary>
        public double? GustPercent { get; set; }
    }

    public class AdvancedCoachResponse {
        public double? BacklashMs { get; set; }
        public double? BacklashArcsec { get; set; }

        /// <summary>Measured, None (no backlash), Unreliable (e.g. Dec drift too strong, star lost) or Skipped.</summary>
        public string BacklashState { get; set; }

        /// <summary>Dec position (arcsec) vs cumulative pulse time (ms) of the backlash test, for plotting (X = ms, Y = arcsec).</summary>
        public List<AdvancedCoachPoint> BacklashPoints { get; set; } = new List<AdvancedCoachPoint>();
        public List<AdvancedCoachPulse> Pulses { get; set; } = new List<AdvancedCoachPulse>();
        public int? MinEffectivePulseRaMs { get; set; }
        public int? MinEffectivePulseDecMs { get; set; }

        /// <summary>West/East and North/South move ratios (1 = symmetric).</summary>
        public double? AsymmetryRa { get; set; }
        public double? AsymmetryDec { get; set; }

        /// <summary>Measured / calibrated rate.</summary>
        public double? RateRatioRa { get; set; }
        public double? RateRatioDec { get; set; }
    }

    public class AdvancedCoachPoint {
        public double X { get; set; }
        public double Y { get; set; }
    }

    public class AdvancedCoachPulse {
        /// <summary>West, East, North or South.</summary>
        public string Direction { get; set; }
        public int DurationMs { get; set; }
        public double ExpectedArcsec { get; set; }
        public double MovedArcsec { get; set; }

        /// <summary>Moved / expected.</summary>
        public double Ratio { get; set; }
    }

    public class AdvancedCoachTrial {
        /// <summary>A (current), B (suggestion), C (variant), A2 (current again).</summary>
        public string Id { get; set; }

        /// <summary>current, suggestion, variant or currentRepeat.</summary>
        public string Kind { get; set; }

        /// <summary>Settings that differ from the current settings (empty for A/A2).</summary>
        public List<AdvancedCoachSettingChange> Settings { get; set; } = new List<AdvancedCoachSettingChange>();

        /// <summary>Pending, Settling, Running, Done, Skipped or Failed.</summary>
        public string State { get; set; }
        public double ElapsedSeconds { get; set; }
        public int Frames { get; set; }
        public double? RmsRaArcsec { get; set; }
        public double? RmsDecArcsec { get; set; }
        public double? RmsTotalArcsec { get; set; }
        public double? PeakArcsec { get; set; }
        public double? OscillationIndex { get; set; }
        public double? SnrAvg { get; set; }
        public bool IsWinner { get; set; }
        public bool Applied { get; set; }
    }

    public class AdvancedCoachSettingChange {
        /// <summary>Guider setting name (<see cref="AdvancedGuiderSetting.Name"/>).</summary>
        public string Name { get; set; }

        /// <summary>New value, invariant culture.</summary>
        public string Value { get; set; }

        /// <summary>Value at the time of the finding, invariant culture.</summary>
        public string CurrentValue { get; set; }
    }

    public class AdvancedCoachFinding {
        /// <summary>Unique within a session/report: the code, plus ":&lt;qualifier&gt;" for repeated codes (e.g. response.minPulse:Ra).</summary>
        public string Id { get; set; }

        /// <summary>Stable code for localised teaching texts, e.g. drift.polarAlignment, hint.raOscillation.</summary>
        public string Code { get; set; }

        /// <summary>CameraCheck, Drift, MountResponse, Trials, Report or Live.</summary>
        public string Step { get; set; }

        /// <summary>good, info, warning or problem.</summary>
        public string Severity { get; set; }

        /// <summary>Numbers (double) and strings for the text templates, e.g. { "arcmin": 7.3, "decAssumed": false }.</summary>
        public Dictionary<string, object> Parameters { get; set; } = new Dictionary<string, object>();

        /// <summary>Estimated total RMS improvement (arcsec) if fixed; used to rank actions.</summary>
        public double? ImpactArcsec { get; set; }

        /// <summary>Setting changes applied by <see cref="IAdvancedGuider.ApplyCoachActions"/> (empty for advice only).</summary>
        public List<AdvancedCoachSettingChange> Changes { get; set; } = new List<AdvancedCoachSettingChange>();
        public bool Applied { get; set; }

        /// <summary>English fallback text (logs; UIs render from <see cref="Code"/>).</summary>
        public string Message { get; set; }
        public DateTime Timestamp { get; set; }

        /// <summary>Live hints only: when the hint stops being shown.</summary>
        public DateTime? ExpiresAt { get; set; }
    }

    public class AdvancedCoachReport {
        public string Id { get; set; }
        public DateTime Timestamp { get; set; }

        /// <summary>Observing night (noon to noon), yyyy-MM-dd.</summary>
        public string Night { get; set; }
        public string ProfileName { get; set; }
        public string CameraName { get; set; }
        public double? FocalLengthMm { get; set; }

        /// <summary>Guide pixel scale, arcsec/px.</summary>
        public double PixelScale { get; set; }

        /// <summary>Imaging camera scale from the profile, arcsec/px (null when unknown).</summary>
        public double? ImagingScale { get; set; }
        public double? DeclinationDeg { get; set; }
        public string PierSide { get; set; }

        /// <summary>Steps that ran (Done).</summary>
        public List<string> Steps { get; set; } = new List<string>();

        /// <summary>Guided RMS (from the best trial, else the last guiding window) and where it came from: trials, window or none.</summary>
        public double? GuidedRmsArcsec { get; set; }
        public double? GuidedRmsRaArcsec { get; set; }
        public double? GuidedRmsDecArcsec { get; set; }
        public string GuidedSource { get; set; }

        /// <summary>Error budget (arcsec RMS, quadrature): seeing + centroid noise + mount/other = guided.</summary>
        public double? SeeingArcsec { get; set; }
        public double? CentroidNoiseArcsec { get; set; }
        public double? MountArcsec { get; set; }
        public double? BacklashArcsec { get; set; }
        public double? PolarAlignmentErrorArcmin { get; set; }
        public double? PeriodicErrorAmplitudeArcsec { get; set; }

        /// <summary>excellent, good, fair, poor or unknown.</summary>
        public string Grade { get; set; }

        /// <summary>Guided RMS / imaging scale (or guided RMS in arcsec when no imaging scale is known).</summary>
        public double? GradeRatio { get; set; }

        /// <summary>Ranked action ids (findings with warning/problem, biggest impact first).</summary>
        public List<string> Actions { get; set; } = new List<string>();
        public List<AdvancedCoachFinding> Findings { get; set; } = new List<AdvancedCoachFinding>();
        public AdvancedCoachCameraCheck Camera { get; set; }
        public AdvancedCoachDrift Drift { get; set; }
        public AdvancedCoachResponse Response { get; set; }
        public List<AdvancedCoachTrial> Trials { get; set; } = new List<AdvancedCoachTrial>();
    }
}
