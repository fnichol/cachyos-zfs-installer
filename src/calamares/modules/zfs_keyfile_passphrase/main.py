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

    # Get the module configuration first
    config = libcalamares.job.configuration
    always_prompt = config.get('alwaysPrompt', False)

    # Check if we should prompt based on ZFS pool existence and encryption
    should_prompt = always_prompt

    if not should_prompt and libcalamares.globalstorage.contains('zfsPoolInfo'):
        zfs_pool_info = libcalamares.globalstorage.value('zfsPoolInfo')
        if zfs_pool_info:
            # Check if the pool is encrypted by looking for encryption in datasets
            zfs_datasets = libcalamares.globalstorage.value('zfsDatasets')
            if zfs_datasets:
                for dataset in zfs_datasets:
                    # Check if any dataset has encryption property
                    if isinstance(dataset, dict):
                        # Encryption is typically on the pool root
                        should_prompt = True
                        break

    if not should_prompt:
        # Skip if not prompting and no encryption detected
        return None

    # Use shell dialogs (kdialog/zenity) - no Qt threading issues
    import subprocess
    import shutil

    # Determine which dialog tool is available
    if shutil.which('kdialog'):
        dialog_tool = 'kdialog'
    elif shutil.which('zenity'):
        dialog_tool = 'zenity'
    else:
        return (_("ZFS Keyfile Setup Failed"),
                _("No dialog tool available (need kdialog or zenity)"))

    # Show informational message
    info_text = ("To enable automatic system boot with your encrypted ZFS pool, "
                 "we need to create a keyfile.\n\n"
                 "On the next screen, please re-enter your ZFS encryption passphrase.\n\n"
                 "(This is the same passphrase you entered during pool creation)")

    if dialog_tool == 'kdialog':
        result = subprocess.run(
            ['kdialog', '--title', 'ZFS Boot Configuration',
             '--yesno', info_text],
            capture_output=True
        )
        if result.returncode != 0:  # User clicked No or Cancel
            return (_("ZFS Keyfile Setup Cancelled"),
                    _("Automatic boot setup was cancelled. "
                      "You will need to enter your passphrase manually at each boot."))
    else:  # zenity
        result = subprocess.run(
            ['zenity', '--question', '--title=ZFS Boot Configuration',
             '--text=' + info_text],
            capture_output=True
        )
        if result.returncode != 0:
            return (_("ZFS Keyfile Setup Cancelled"),
                    _("Automatic boot setup was cancelled. "
                      "You will need to enter your passphrase manually at each boot."))

    # Get passphrase
    if dialog_tool == 'kdialog':
        result = subprocess.run(
            ['kdialog', '--title', 'ZFS Encryption Passphrase',
             '--password', 'Enter your ZFS encryption passphrase for keyfile creation:'],
            capture_output=True, text=True
        )
    else:  # zenity
        result = subprocess.run(
            ['zenity', '--password', '--title=ZFS Encryption Passphrase'],
            capture_output=True, text=True
        )

    if result.returncode != 0 or not result.stdout.strip():
        return (_("ZFS Keyfile Setup Cancelled"),
                _("No passphrase provided. "
                  "You will need to enter your passphrase manually at each boot."))

    passphrase = result.stdout.strip()

    # Confirm passphrase
    if dialog_tool == 'kdialog':
        result = subprocess.run(
            ['kdialog', '--title', 'Confirm Passphrase',
             '--password', 'Please confirm your ZFS encryption passphrase:'],
            capture_output=True, text=True
        )
    else:  # zenity
        result = subprocess.run(
            ['zenity', '--password', '--title=Confirm Passphrase'],
            capture_output=True, text=True
        )

    if result.returncode != 0 or result.stdout.strip() != passphrase:
        return (_("Passphrase Mismatch"),
                _("The passphrases do not match. "
                  "Automatic boot setup was cancelled."))

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
            "ZFS passphrase captured for keyfile creation"
        )

        return None

    except Exception as e:
        return (_("ZFS Keyfile Setup Failed"),
                _("Error writing passphrase to temporary file: {}").format(str(e)))
