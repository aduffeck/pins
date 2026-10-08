#region "copyright"

/*
    Copyright © 2026 Nico Trost <nico.trost57@gmail.com> and the PI.N.S. contributors

    This file is part of PI 'N' Stars.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

using NINA.INDI.Devices;
using NINA.INDI.Enums;
using NINA.INDI.Protocol;
using NUnit.Framework;
using System;
using System.Collections.Generic;

namespace NINA.Test.INDI {

    [TestFixture]
    public class PulseGuideTrackerTest {
        private const string NS = PulseGuideTracker.NorthSouth;
        private const string WE = PulseGuideTracker.WestEast;
        private static readonly TimeSpan Margin = PulseGuideTracker.CompletionMargin;

        private DateTime now;
        private PulseGuideTracker tracker = null!;
        private List<(string Property, int DurationMs)> timeouts = null!;

        [SetUp]
        public void SetUp() {
            now = new DateTime(2026, 10, 8, 22, 0, 0, DateTimeKind.Utc);
            tracker = new PulseGuideTracker(() => now);
            timeouts = [];
            tracker.TimedOut += (property, durationMs) => timeouts.Add((property, durationMs));
        }

        private static INDINumberProperty GuideVector(string name, PropertyState state, double first = 0, double second = 0) {
            var (a, b) = name == NS ? ("TIMED_GUIDE_N", "TIMED_GUIDE_S") : ("TIMED_GUIDE_W", "TIMED_GUIDE_E");
            return new INDINumberProperty {
                Name = name,
                State = state,
                Numbers = { new INDINumber { Name = a, Value = first }, new INDINumber { Name = b, Value = second } }
            };
        }

        [Test]
        public void SentPulse_IsGuiding_BeforeTheDriverReplies() {
            tracker.PulseSending(NS, 300);

            Assert.That(tracker.IsPulseGuiding, Is.True);
        }

        [TestCase(PropertyState.Ok)]
        [TestCase(PropertyState.Idle)]
        [TestCase(PropertyState.Alert)]
        public void Busy_KeepsGuiding_UntilTheFirstUpdateThatIsNotBusy(PropertyState end) {
            tracker.PulseSending(NS, 300);
            tracker.Observe(GuideVector(NS, PropertyState.Busy, 300));
            now += TimeSpan.FromMilliseconds(200);
            Assert.That(tracker.IsPulseGuiding, Is.True);

            tracker.Observe(GuideVector(NS, end, 300));

            Assert.That(tracker.IsPulseGuiding, Is.False);
            Assert.That(timeouts, Is.Empty);
        }

        [Test]
        public void DriverAnsweringOkWithoutBusy_EndsThePulse() {
            tracker.PulseSending(WE, 300);

            tracker.Observe(GuideVector(WE, PropertyState.Ok, 300));

            Assert.That(tracker.IsPulseGuiding, Is.False);
        }

        [Test]
        public void UpdateOfTheOtherAxis_DoesNotEndThePulse() {
            tracker.PulseSending(NS, 300);

            tracker.Observe(GuideVector(WE, PropertyState.Idle));

            Assert.That(tracker.IsPulseGuiding, Is.True);
        }

        [Test]
        public void NoReply_EndsAtPulseLengthPlusMargin_AndReportsATimeout() {
            tracker.PulseSending(NS, 300);

            now += TimeSpan.FromMilliseconds(300) + Margin - TimeSpan.FromMilliseconds(1);
            Assert.That(tracker.IsPulseGuiding, Is.True);
            Assert.That(timeouts, Is.Empty);

            now += TimeSpan.FromMilliseconds(1);
            Assert.That(tracker.IsPulseGuiding, Is.False);
            Assert.That(timeouts, Is.EqualTo(new[] { (NS, 300) }));

            Assert.That(tracker.IsPulseGuiding, Is.False);
            Assert.That(timeouts, Has.Count.EqualTo(1), "a timeout is reported once");
        }

        [Test]
        public void StuckBusy_EndsAtTheDeadline() {
            tracker.PulseSending(WE, 200);
            tracker.Observe(GuideVector(WE, PropertyState.Busy, 200));

            now += TimeSpan.FromMilliseconds(200) + Margin;

            Assert.That(tracker.IsPulseGuiding, Is.False);
            Assert.That(timeouts, Is.EqualTo(new[] { (WE, 200) }));
        }

        [Test]
        public void LateBusy_ExtendsTheDeadline_ForADriverThatStartedThePulseLate() {
            tracker.PulseSending(NS, 1000);
            now += TimeSpan.FromMilliseconds(800);
            tracker.Observe(GuideVector(NS, PropertyState.Busy, 1000));

            now += TimeSpan.FromMilliseconds(1000) + Margin - TimeSpan.FromMilliseconds(1);

            Assert.That(tracker.IsPulseGuiding, Is.True);
        }

        [Test]
        public void BusyFromTheDriver_WithoutAPulseSentHere_CountsAsGuiding() {
            tracker.Observe(GuideVector(NS, PropertyState.Busy, 0, 400));

            Assert.That(tracker.IsPulseGuiding, Is.True);
            now += TimeSpan.FromMilliseconds(400) + Margin;
            Assert.That(tracker.IsPulseGuiding, Is.False);
        }

        [Test]
        public void PulseNotSent_IsNotGuiding() {
            tracker.PulseSending(NS, 300);

            tracker.PulseNotSent(NS);

            Assert.That(tracker.IsPulseGuiding, Is.False);
            now += TimeSpan.FromSeconds(5);
            Assert.That(tracker.IsPulseGuiding, Is.False);
            Assert.That(timeouts, Is.Empty);
        }

        [Test]
        public void BothAxes_AreTrackedSeparately() {
            tracker.PulseSending(NS, 300);
            tracker.PulseSending(WE, 300);

            tracker.Observe(GuideVector(NS, PropertyState.Ok));
            Assert.That(tracker.IsPulseGuiding, Is.True, "the RA pulse is still running");

            tracker.Observe(GuideVector(WE, PropertyState.Ok));
            Assert.That(tracker.IsPulseGuiding, Is.False);
        }
    }
}
