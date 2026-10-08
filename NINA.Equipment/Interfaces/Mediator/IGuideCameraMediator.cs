#region "copyright"

/*
    Copyright © 2026 Nico Trost <nico.trost57@gmail.com> and the PI.N.S. contributors

    This file is part of PI 'N' Stars.

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#endregion "copyright"

namespace NINA.Equipment.Interfaces.Mediator {

    /// <summary>
    /// The guide camera slot: a second camera next to the imaging camera, with its own settings
    /// (Profile.GuideCameraSettings). Guiders import this; ICameraMediator is always the imaging camera.
    /// </summary>
    public interface IGuideCameraMediator : ICameraMediator {
    }
}
