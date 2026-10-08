#region "copyright"

/*
    Copyright © 2026 Nico Trost <nico.trost57@gmail.com> and the PI.N.S. contributors

    This file is part of PI 'N' Stars.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

using NINA.INDI.Enums;
using NINA.INDI.Protocol;
using System;
using System.Collections.Generic;
using System.Linq;

namespace NINA.INDI.Devices {

    /// <summary>
    /// Whether a timed guide pulse is in progress, per axis. INDI has no "is guiding" flag, and the driver's Busy
    /// state arrives only after the pulse was sent, so like PHD2's ScopeINDI an axis counts as guiding from the
    /// moment its pulse is sent until the first update of its TELESCOPE_TIMED_GUIDE_* property that is not Busy.
    /// Unlike PHD2 the wait is bounded: a driver that never reports the end of a pulse releases the axis
    /// <see cref="CompletionMargin"/> after the pulse should have ended, and <see cref="TimedOut"/> reports it.
    /// </summary>
    internal sealed class PulseGuideTracker {
        public const string NorthSouth = "TELESCOPE_TIMED_GUIDE_NS";
        public const string WestEast = "TELESCOPE_TIMED_GUIDE_WE";

        /// <summary>
        /// Added to a pulse before an unreported end counts as a timeout. Covers a driver that starts the pulse late,
        /// e.g. behind its own status poll on the serial port; the end merely reaching pins late does not matter, as
        /// the mount has stopped by then.
        /// </summary>
        public static readonly TimeSpan CompletionMargin = TimeSpan.FromMilliseconds(500);

        private readonly Func<DateTime> utcNow;
        private readonly object sync = new();
        private readonly Dictionary<string, (DateTime Deadline, int DurationMs)> active = [];

        public PulseGuideTracker(Func<DateTime> utcNow = null) {
            this.utcNow = utcNow ?? (() => DateTime.UtcNow);
        }

        /// <summary>Raised outside the tracker's lock with the guide property and the pulse length in ms.</summary>
        public event Action<string, int> TimedOut;

        public bool IsPulseGuiding {
            get {
                bool guiding;
                List<(string, int)> expired;
                lock (sync) {
                    expired = ExpireOverdue();
                    guiding = active.Count > 0;
                }
                Report(expired);
                return guiding;
            }
        }

        /// <summary>Call right before sending the pulse, so the driver's reply can never arrive before the axis is marked.</summary>
        public void PulseSending(string property, int durationMs) {
            List<(string, int)> expired;
            lock (sync) {
                expired = ExpireOverdue();
                active[property] = (utcNow() + TimeSpan.FromMilliseconds(Math.Max(0, durationMs)) + CompletionMargin, durationMs);
            }
            Report(expired);
        }

        /// <summary>The pulse could not be sent, so no reply will come.</summary>
        public void PulseNotSent(string property) {
            lock (sync) {
                active.Remove(property);
            }
        }

        /// <summary>Feed every update of the timed-guide properties.</summary>
        public void Observe(INDINumberProperty p) {
            if (p.Name != NorthSouth && p.Name != WestEast) {
                return;
            }

            lock (sync) {
                if (p.State != PropertyState.Busy) {
                    active.Remove(p.Name);
                    return;
                }

                // Busy: the driver has started a pulse, ours or another client's. It ends one pulse length from
                // now at the latest, which also covers a driver that started ours late.
                var durationMs = (int)Math.Max(0, p.Numbers.Select(n => n.Value).DefaultIfEmpty(0).Max());
                var deadline = utcNow() + TimeSpan.FromMilliseconds(durationMs) + CompletionMargin;
                if (active.TryGetValue(p.Name, out var pending) && pending.Deadline > deadline) {
                    deadline = pending.Deadline;
                    durationMs = pending.DurationMs;
                }
                active[p.Name] = (deadline, durationMs);
            }
        }

        // Caller holds sync.
        private List<(string, int)> ExpireOverdue() {
            var now = utcNow();
            var expired = active.Where(a => a.Value.Deadline <= now).Select(a => (a.Key, a.Value.DurationMs)).ToList();
            foreach (var (property, _) in expired) {
                active.Remove(property);
            }
            return expired;
        }

        private void Report(List<(string Property, int DurationMs)> expired) {
            foreach (var (property, durationMs) in expired) {
                TimedOut?.Invoke(property, durationMs);
            }
        }
    }
}
