#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# SPDX-FileCopyrightText: 2024
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prompts user for ZFS encryption passphrase to create keyfile for automatic boot

import libcalamares
from libcalamares.utils import gettext_path, gettext_languages
import os

import gettext

_translation = gettext.translation("calamares-python",
                                   localedir=gettext_path(),
                                   languages=gettext_languages(),
                                   fallback=True)
_ = _translation.gettext
_n = _translation.ngettext


def pretty_name():
    return _("ZFS Keyfile Setup")


def run():
    """
    Prompts the user for their ZFS encryption passphrase to create a keyfile
    for automatic system boot.

    Returns None on success, or (error_title, error_description) on failure.
    """

    # Check if we should prompt based on ZFS pool existence and encryption
    should_prompt = False
    passphrase = None

    if not should_prompt and libcalamares.globalstorage.contains('zfsInfo'):
        entries = libcalamares.globalstorage.value('zfsInfo')
        if entries:
            for zfs_info in entries:
                should_prompt = zfs_info["encrypted"]
                passphrase = zfs_info["passphrase"]

    if not should_prompt:
        # Skip if not prompting and no encryption detected
        return None

    try:
        # Write passphrase to temporary file on live system
        # (rootMountPoint not available yet - mount module runs later)
        temp_dir = '/tmp'
        temp_file = os.path.join(temp_dir, '.zfs_passphrase')

        # Create file with 0600 permissions
        fd = os.open(temp_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            # Write passphrase (without trailing newline!)
            os.write(fd, passphrase.encode('utf-8'))
        finally:
            os.close(fd)

        # Store the temp file path in global storage for shellprocess to find
        libcalamares.globalstorage.insert('zfs_passphrase_file',
                                          '/tmp/.zfs_passphrase')

        libcalamares.utils.debug(
            "ZFS passphrase captured for keyfile creation")

        return None

    except Exception as e:
        return (_("ZFS Keyfile Setup Failed"),
                _("Error writing passphrase to temporary file: {}").format(
                    str(e)))
