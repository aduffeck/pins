#region "copyright"

/*
    Copyright © 2026 Nico Trost <nico.trost57@gmail.com> and the PI.N.S. contributors

    This file is part of PI 'N' Stars.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

using Moq;
using NINA.Equipment.Equipment;
using NINA.Equipment.Equipment.MyCamera;
using NINA.Equipment.Interfaces;
using NINA.Equipment.Interfaces.ViewModel;
using NINA.Equipment.SDK.CameraSDKs.PlayerOneSDK;
using NINA.Equipment.SDK.CameraSDKs.SVBonySDK;
using NINA.Image.Interfaces;
using NINA.Profile;
using NINA.Profile.Interfaces;
using NINA.WPF.Base.ViewModel.Equipment.Camera;
using NUnit.Framework;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using ProfileModel = NINA.Profile.Profile;

namespace NINA.Test.ViewModel {

    /// <summary>
    /// The parts of the guide camera slot that decide which cameras its list offers. GuideCameraVM itself adds
    /// nothing to CameraVM but its title, and CameraVM tests need STA, which doesn't run on Linux.
    /// </summary>
    [TestFixture]
    public class GuideCameraSlotTest {
        private ProfileModel profile = null!;
        private IProfileService imaging = null!;
        private GuideCameraProfileService guide = null!;
        private IExposureDataFactory exposureDataFactory = null!;

        [SetUp]
        public void SetUp() {
            profile = new ProfileModel("Rig");
            var profileService = new Mock<IProfileService>();
            profileService.SetupGet(s => s.ActiveProfile).Returns(profile);
            imaging = profileService.Object;
            guide = new GuideCameraProfileService(imaging);
            exposureDataFactory = Mock.Of<IExposureDataFactory>();
        }

        [TearDown]
        public void TearDown() {
            profile.Dispose();
        }

        private Task<IList<IEquipmentProvider<ICamera>>> GuideProvidersOf(params IEquipmentProvider<ICamera>[] providers) {
            var cameraProviders = new Mock<IEquipmentProviders<ICamera>>();
            cameraProviders.Setup(p => p.GetProviders()).ReturnsAsync(providers.ToList());
            return new GuideCameraEquipmentProviders(cameraProviders.Object, guide, exposureDataFactory).GetProviders();
        }

        private static object? ProfileServiceOf(object provider) {
            return provider.GetType().GetField("profileService", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(provider);
        }

        [Test]
        public async Task PlayerOneAndSVBony_AreRebuiltWithTheGuideCamerasSettings() {
            var providers = await GuideProvidersOf(
                new PlayerOneProvider(imaging, exposureDataFactory, Mock.Of<IPlayerOnePInvokeProxy>()),
                new SVBonyProvider(imaging, exposureDataFactory, Mock.Of<ISVBonyPInvokeProxy>()));

            Assert.That(providers.Select(p => p.GetType()), Is.EqualTo(new[] { typeof(PlayerOneProvider), typeof(SVBonyProvider) }));
            Assert.That(providers.Select(ProfileServiceOf), Is.All.SameAs(guide));
        }

        [Test]
        public async Task OtherProviders_AreLeftOut() {
            var thirdParty = Mock.Of<IEquipmentProvider<ICamera>>(p => p.Name == "Third Party");

            var providers = await GuideProvidersOf(thirdParty, new PlayerOneProvider(imaging, exposureDataFactory, Mock.Of<IPlayerOnePInvokeProxy>()));

            Assert.That(providers.Select(p => p.GetType()), Is.EqualTo(new[] { typeof(PlayerOneProvider) }));
        }

        [Test]
        public void AlpacaDirect_IsNotOfferedAsGuideCamera() {
            var alpacaDirect = new AlpacaDirectCamera(guide, exposureDataFactory);

            Assert.That(alpacaDirect.Id, Is.EqualTo(GuideCameraChooserVM.AlpacaDirectCameraId));
            Assert.That(GuideCameraChooserVM.IsOffered(alpacaDirect), Is.False);
        }

        [Test]
        public void OtherCameras_AndNoCamera_AreOffered() {
            Assert.That(GuideCameraChooserVM.IsOffered(Mock.Of<ICamera>()), Is.True);
            Assert.That(GuideCameraChooserVM.IsOffered(new DummyDevice("No camera")), Is.True);
        }
    }
}
