#!/bin/bash

## Global Functions ##

# --- Logging Functions ---

# Create a log file
LOG_FILE="/var/log/archl4tm.log"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "${LOG_FILE}_error.log" >&2)
touch "$LOG_FILE"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Set the color using tput
    case "$level" in
        DEBUG) color=$(tput setaf 4);;  # Blue for debug
        INFO) color=$(tput setaf 3);;   # Yellow for info
        WARN) color=$(tput setaf 3);;   # Yellow for warn
        ERROR) color=$(tput setaf 1);;  # Red for error
        *) color=$(tput sgr0);;      # Reset color
    esac

    # Format the message with timestamp and color
   formatted_message=$(printf "[%s] [%s%s%s] %s" "$timestamp" "$color" "$level" "$(tput sgr0)" "$message")

    # Print the message to the console
    echo "${formatted_message}"

    # Append the message to the log file (without color)
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

log_debug() {
    log "DEBUG" "$1"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_error() {
    log "ERROR" "$1"
}

validate_username() {
    local username="$1"
    if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then
        return 0  # True
    else
        log_error "Invalid username: $username"
        return 1  # False
    fi
}

validate_hostname() {
    local hostname="$1"
    if [[ "${hostname,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]; then
        return 0  # True
    else
        log_error "Invalid hostname: $hostname" 1
        return 1  # False
    fi
}

validate_disk() {
    local disk="$1"
    if [ -b "$disk" ]; then
        return 0  # True
    else
        log_error "Invalid disk path: $disk"
        return 1  # False
    fi
}

# --- Confirmation Function ---
confirm_action() {
    local message="$1"
    read -r -p "$message (Y/n) " confirm
    confirm=${confirm,,}  # Convert to lowercase

    # Check if confirm is "y" or empty
    if [[ "$confirm" == "y" ]] || [[ -z "$confirm" ]]; then  
        return 0  # True
    else
        return 1  # False
    fi
}

# --- User Input Functions --- #
# --- Ask for desired username ---
get_username() {
    while true; do
        read -r -p "Enter a username: " username

        if ! validate_username "$username"; then
            continue
        fi

        export USERNAME="$username"
        log_info "Username set to: $USERNAME"
        break
    done
}

# --- Ask for desired user password ---
get_user_password() {
    while true; do
        read -rs -p "Set a password for $USERNAME: " USER_PASSWORD1
        echo
        read -rs -p "Confirm password: " USER_PASSWORD2
        echo

        if [[ "$USER_PASSWORD1" != "$USER_PASSWORD2" ]]; then
            log_error "Passwords do not match." 1
            continue
        fi

        export USER_PASSWORD="$USER_PASSWORD1"
        log_info "Password set for $USERNAME successfully."
        break
    done
}

# --- Ask for desired root password ---
get_root_password() {
    while true; do
        read -rs -p "Set root password: " ROOT_PASSWORD1
        echo
        read -rs -p "Confirm root password: " ROOT_PASSWORD2
        echo

        if [[ "$ROOT_PASSWORD1" != "$ROOT_PASSWORD2" ]]; then
            log_error "Passwords do not match." 1
            continue
        fi

        export ROOT_PASSWORD="$ROOT_PASSWORD1"
        log_info "Root password set successfully."
        break
    done
}

# --- Ask for desired hostname ---
get_hostname() {
    while true; do
        read -r -p "Enter a hostname: " hostname

        if ! validate_hostname "$hostname"; then
            continue
        fi

        export HOSTNAME="$hostname"
        log_info "Hostname set to: $HOSTNAME"
        break
    done
}

# --- Ask which disk to use ---
get_disk() {
    # List Disks
    log_info "Available disks:"
    fdisk -l | grep "Disk /"

    while true; do
        read -r -p "Enter the disk to use (e.g. /dev/nvme0n1 , /dev/sda): " disk

        if ! validate_disk "$disk"; then
            continue
        fi

        # Confirm Disk Selection using confirm_action from functions.sh
        if confirm_action "You have selected $disk. Is this correct?"; then
            export DISK="$disk"
            log_info "Disk set to: $DISK"
            break
        fi
    done
}

# --- Ask for desired partition sizes ---
get_partition_sizes() {
    while true; do
        read -r -p "Enter EFI partition size (e.g., 512M, 1G): " efi_size
        read -r -p "Enter boot partition size (e.g., 512M, 1G): " boot_size

        # Basic validation
        if [[ "$efi_size" =~ ^[0-9]+(G|M|K)$ ]] && \
           [[ "$boot_size" =~ ^[0-9]+(G|M|K)$ ]]; then
            export EFI_SIZE="$efi_size"
            export BOOT_SIZE="$boot_size"
            log_info "EFI partition size: $EFI_SIZE"
            log_info "Boot partition size: $BOOT_SIZE"
            break
        else
            log_error "Invalid partition size(s). Please use a format like 512M or 1G." 1
        fi
    done
}

# --- Ask for desired encryption password ---
get_encryption_password() {
    while true; do
        read -rs -p "Enter encryption password: " password
        echo
        read -rs -p "Confirm encryption password: " confirm_password
        echo

        if [[ "$password" != "$confirm_password" ]]; then
            log_error "Passwords do not match." 1
            continue
        fi

        export ENCRYPTION_PASSWORD="$password"
        log_info "Encryption password set."
        break
    done
}

select_timezone() {
    log_info "Please enter a partial or full timezone name (e.g., 'New_York', 'America'):"
    read -r timezone_search

    filtered_timezones=$(timedatectl list-timezones | grep -i "$timezone_search")

    if [[ -z "$filtered_timezones" ]]; then
        log_error "No timezones found matching '$timezone_search'. Using default (UTC)."
        echo "UTC"
    else
        # Count the number of filtered timezones
        num_timezones=$(echo "$filtered_timezones" | wc -l)

        if [[ $num_timezones -eq 1 ]]; then
            # If there's only one option, select it automatically
            ACTUAL_TIMEZONE=$(echo "$filtered_timezones")
            log_info "Automatically selected the only matching timezone: $ACTUAL_TIMEZONE"
            echo "$ACTUAL_TIMEZONE"
            export ACTUAL_TIMEZONE=$ACTUAL_TIMEZONE
        else
            # Otherwise, use `select` with scrolling using fzf
            ACTUAL_TIMEZONE=$(echo "$filtered_timezones" | fzf --tac)  # Use fzf for scrolling
            if [[ -n "$ACTUAL_TIMEZONE" ]]; then
                echo "$ACTUAL_TIMEZONE"
                export ACTUAL_TIMEZONE=$ACTUAL_TIMEZONE
            else
                log_error "No timezone selected. Using default (UTC)."
                echo "UTC"
            fi
        fi
    fi
}

set_timezone() {
    # Use $ACTUAL_TIMEZONE directly
    if [[ -z "$ACTUAL_TIMEZONE" ]]; then
        log_error "Timezone not provided. Using default (UTC)."
        timedatectl set-timezone UTC
    else
        log_info "Setting timezone to $ACTUAL_TIMEZONE"
        timedatectl set-timezone "$ACTUAL_TIMEZONE"
    fi
}

# --- Ask for desired server/desktop ---
select_gui() {
    log_info "Selecting GUI..."

    options=("Server (No GUI)" "Hyprland" "GNOME" "KDE Plasma")
    select gui_choice in "${options[@]}"; do
        case "$gui_choice" in
            "Hyprland")
                export GUI_CHOICE="hyprland"
                log_info "Hyprland selected."
                ;;
            "GNOME")
                export GUI_CHOICE="gnome"
                log_info "GNOME selected."
                ;;
            "KDE Plasma")
                export GUI_CHOICE="kde"
                log_info "KDE Plasma selected."
                ;;
            *)
                export GUI_CHOICE="none"
                log_info "No GUI selected."
                ;;
        esac
        break
    done
}

# --- Ask for desired GRUB theme ---
get_grub_theme() {
  log_info "Selecting GRUB Theme..."

  # Ask the user if they want to install a GRUB Theme
  if ! confirm_action "Do you want to install a GRUB Theme?"; then
    log_info "Skipping GRUB Theme installation."
    export GRUB_THEME="none" 
    return 0
  fi

  # Ask the user which GRUB Theme they want
  options=("poly-dark" "CyberEXS" "Cyberpunk" "HyperFluent" "none")
  while true; do
    select grub_theme in "${options[@]}"; do
      case "$grub_theme" in
        poly-dark)
          export GRUB_THEME="poly-dark" 
          log_info "poly-dark selected."
          break 
          ;;
        CyberEXS)
          export GRUB_THEME="CyberEXS" 
          log_info "CyberEXS selected."
          break 
          ;;
        Cyberpunk)
          export GRUB_THEME="Cyberpunk"
          log_info "Cyberpunk selected."
          break 
          ;;
        HyperFluent)
          export GRUB_THEME="HyperFluent" 
          log_info "HyperFluent selected."
          break 
          ;;
        none)
          export GRUB_THEME="none" 
          log_info "No GRUB Theme selected."
          break 
          ;;
        *)
          log_info "Invalid option. Please select a valid theme." 
          ;; 
      esac
    done
    break
  done
}

# --- Ask for desired AUR helper ---
get_aur_helper() {
    log_info "Selecting AUR helper..."

    # Ask the user if they want to install an AUR helper
    if ! confirm_action "Do you want to install an AUR helper?"; then
        log_info "Skipping AUR helper installation."
        export AUR_HELPER="none"
        return 0
    fi

    # Ask the user which AUR helper they want
    options=("paru" "yay" "none")
    select aur_helper in "${options[@]}"; do
        case "$aur_helper" in
            paru)
                export AUR_HELPER="paru"
                log_info "paru selected."
                ;;
            yay)
                export AUR_HELPER="yay"
                log_info "yay selected."
                ;;
            none)
                export AUR_HELPER="none"
                log_info "No AUR helper selected."
                ;;
            *)
            log_info "Invalid option. Skipping AUR helper installation."
            export AUR_HELPER="none"
            exit 1
            ;;
    esac
    break
done
}

# --- Disk Setup ---
partition_disk() {
    local disk="$1"
    local efi_size="$2"
    local boot_size="$3"

    log_info "Partitioning disk: $disk"

    # Create new GPT partition table
    if ! sgdisk --zap-all "$disk"; then
        log_error "Failed to clear disk" $?
        exit 1
    fi

    # Create EFI partition
    if ! sgdisk -n 1:0:+"$efi_size" -t 1:EF00 "$disk"; then
        log_error "Failed to create EFI partition" $?
        exit 1
    fi

    # Create boot partition
    if ! sgdisk -n 2:0:+"$boot_size" -t 2:8300 "$disk"; then
        log_error "Failed to create boot partition" $?
        exit 1
    fi

    # Create LVM partition (using remaining space)
    if ! sgdisk -n 3:0:0 -t 3:8E00 "$disk"; then
        log_error "Failed to create LVM partition" $?
        exit 1
    fi

    # Print partition table
    sgdisk -p "$disk"

    # Re-read partition table
    partprobe "$disk"
}

setup_lvm() {
    local disk="$1"
    local password="$2"

    log_info "Setting up LVM on disk: $disk"

    # Format EFI partition
      if [[ $disk =~ nvme ]]; then
          if ! mkfs.fat -F32 "${disk}p1"; then
          log_error "Failed to format EFI partition" $?
          exit 1
      fi
    else
      if ! mkfs.fat -F32 "${disk}1"; then
          log_error "Failed to format EFI partition" $?
          exit 1
      fi
    fi


    # Format boot partition
     if [[ $disk =~ nvme ]]; then 
      if ! mkfs.ext4 "${disk}p2"; then
          log_error "Failed to format boot partition" $?
          exit 1
      fi
    else
      if ! mkfs.ext4 "${disk}2"; then
          log_error "Failed to format boot partition" $?
          exit 1
      fi
    fi 

    # Setup encryption on partition 3 using LUKS
      if [[ $disk =~ nvme ]]; then
        if ! echo "$password" | cryptsetup luksFormat "${disk}p3"; then
          log_error "Failed to format LUKS partition" $?
          exit 1
        fi

    # Open LUKS partition
      if ! echo "$password" | cryptsetup open --type luks --batch-mode "${disk}p3" lvm; then
        log_error "Failed to open LUKS partition" $?
        exit 1
      fi
    else
      if ! echo "$password" | cryptsetup luksFormat "${disk}3"; then
        log_error "Failed to format LUKS partition" $?
        exit 1
      fi

    # Open LUKS partition
      if ! echo "$password" | cryptsetup open --type luks --batch-mode "${disk}3" lvm; then
        log_error "Failed to open LUKS partition" $?
        exit 1
      fi
    fi

    # Create physical volume for LVM on partition 3 with data alignment 1m
    if ! pvcreate /dev/mapper/lvm; then
        log_error "Failed to create physical volume" $?
        exit 1
    fi

    # Create volume group called volgroup0 on partition 3
    if ! vgcreate volgroup0 /dev/mapper/lvm; then
        log_error "Failed to create volume group" $?
        exit 1
    fi

    # Get logical volume sizes from the user
    get_lv_sizes() {
        read -r -p "Enter root logical volume size (e.g., 50G, 100G): " root_lv_size
        export ROOT_LV_SIZE="$root_lv_size"
        log_info "Root logical volume size: $ROOT_LV_SIZE"
    }

    get_lv_sizes

    # Create logical volumes (lv_home will use remaining space)
    if ! lvcreate -L "$ROOT_LV_SIZE" volgroup0 -n lv_root || \
       ! lvcreate -l 100%FREE volgroup0 -n lv_home; then
        log_error "Failed to create logical volumes" $?
        exit 1
    fi

    # Load kernel module
    modprobe dm_mod

    # Scan system for volume groups
    vgscan

    # Activate volume group
    if ! vgchange -ay; then
        log_error "Failed to activate volume group" $?
        exit 1
    fi

    # Format and mount root volume
    if ! mkfs.ext4 /dev/volgroup0/lv_root; then
        log_error "Failed to format root volume" $?
        exit 1
    fi

    if ! mount /dev/volgroup0/lv_root /mnt; then
        log_error "Failed to mount root volume" $?
        exit 1
    fi

    # Create /boot directory and mount partition 2
    if ! mkdir -p /mnt/boot; then
      log_error "Failed to create /boot directory" $?
      exit 1
    fi

    if [[ $disk =~ nvme ]]; then
      if ! mount "${disk}p2" /mnt/boot; then
        log_error "Failed to mount /boot" $?
        exit 1
      fi
    else
      if ! mount "${disk}2" /mnt/boot; then
        log_error "Failed to mount /boot" $?
        exit 1
      fi
    fi

    # Create /boot/EFI directory and mount partition 1
    if ! mkdir -p /mnt/boot/EFI; then
      log_error "Failed to create /boot/EFI directory" $?
      exit 1
    fi

    if [[ $disk =~ nvme ]]; then
      if ! mount "${disk}p1" /mnt/boot/EFI; then
        log_error "Failed to mount /boot/EFI" $?
        exit 1
      fi
    else
      if ! mount "${disk}1" /mnt/boot/EFI; then
        log_error "Failed to mount /boot/EFI" $?
        exit 1
      fi
    fi

    # Format home volume
    if ! mkfs.ext4 /dev/volgroup0/lv_home; then
        log_error "Failed to format home volume" $?
        exit 1
    fi

    # Create /home directory
    if ! mkdir -p /mnt/home; then
        log_error "Failed to create /home directory" $?
        exit 1
    fi

    # Mount home volume
    if ! mount /dev/volgroup0/lv_home /mnt/home; then
        log_error "Failed to mount /home" $?
        exit 1
    fi

    # Ensure /mnt/etc exists
    if ! mkdir -p /mnt/etc; then
        log_error "Failed to create /mnt/etc directory" $?
        exit 1
    fi
}

# --- Install reflector dependencies ---
install_prerequisites() {
    echo -ne "
    #------------------------------#
    # Installing prerequisite pkgs #
    #------------------------------#
    "
    log_info "Installing prerequisite packages..."
    if ! pacman -Sy --noconfirm --needed pacman-contrib reflector rsync; then
        log_error "Failed to install prerequisite packages" $?
        exit 1
    fi
}

# --- Update mirrorlist with reflector ---
configure_mirrors() {
    echo -ne "
    #---------------------#
    # Updating mirrorlist #
    #---------------------#
    "
    log_info "Configuring pacman mirrors for faster downloads..."
    if ! cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup || \
       ! reflector --country US -a 72 -f 10 -l 10 --sort rate --save /etc/pacman.d/mirrorlist; then
        log_error "Failed to configure pacman mirrors" $?
        exit 1
    fi
}

# --- Run pacstrap ---
install_base_packages() {
    echo -ne "
    #------------------#
    # Running pacstrap #
    #------------------#
    "
    log_info "Installing base packages using pacstrap..."
    if ! pacstrap -K /mnt base linux linux-firmware linux-headers --noconfirm --needed; then
        log_error "Failed to install base packages" $?
        exit 1
    fi
}

# --- Configure pacman ---
configure_pacman() {
    echo -ne "
    #--------------------#
    # Configuring Pacman #
    #--------------------#
    "
    log_info "Configuring pacman..."

    if ! sed -i "/^#Color/c\Color\nILoveCandy" /etc/pacman.conf || \
       ! sed -i "/^#VerbosePkgLists/c\VerbosePkgLists" /etc/pacman.conf || \
       ! sed -i "/^#ParallelDownloads/c\ParallelDownloads = 5" /etc/pacman.conf || \
       ! sed -i '/^#\[multilib\]/,+1 s/^#//' /etc/pacman.conf; then
        log_error "Failed to configure pacman" $?
        exit 1
    fi
}

# --- Install microcode ---
install_microcode() {
    echo -ne "
    #----------------------#
    # Installing microcode #
    #----------------------#
    "
    log_info "Installing microcode..."
    proc_type=$(lscpu | grep -oP '^Vendor ID:\s+\K\w+')
    if [ "$proc_type" = "GenuineIntel" ]; then
        log_info "Installing Intel microcode"
        if ! pacman -Sy --noconfirm --needed intel-ucode; then
            log_error "Failed to install Intel microcode" $?
            exit 1
        fi
    elif [ "$proc_type" = "AuthenticAMD" ]; then
        log_info "Installing AMD microcode"
        if ! pacman -Sy --noconfirm --needed amd-ucode; then
            log_error "Failed to install AMD microcode" $?
            exit 1
        fi
    fi
}

# --- Install all pacman packages defined in pkgs.lst ---
install_additional_packages() {
    echo -ne "
    #----------------------------#
    # Installing additional pkgs #
    #----------------------------#
    "
    log_info "Installing additional packages..."
    if ! pacman -S --noconfirm --needed - < ./pkgs.lst; then
        log_error "Failed to install additional packages" $?
        exit 1
    fi
}

# --- Enable system services ---
enable_services() {
    echo -ne "
    #-------------------#
    # Enabling Services #
    #-------------------#
    "
    log_info "Enabling services..."
    if ! systemctl enable NetworkManager.service || \
       ! systemctl enable ntpd.service || \
       ! systemctl enable fstrim.timer; then
        log_error "Failed to enable services" $?
        exit 1
    fi
}

# --- Set locale to en_US.UTF-8 ---
set_locale() {
    echo -ne "
    #----------------#
    # Setting Locale #
    #----------------#
    "
    log_info "Setting locale..."
    if ! sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || \
       ! locale-gen || \
       ! echo 'LANG=en_US.UTF-8' > /etc/locale.conf; then 
        log_error "Failed to set locale" $?
        exit 1
    fi
}

# --- Add HOOKS to mkinitcpoio.conf / Update initramfs --- 
update_initramfs() {
    echo -ne "
    #--------------------#
    # Updating Initramfs #
    #--------------------#
    "
    log_info "Updating initramfs..."
    if ! sed -i 's/^HOOKS\s*=\s*(.*)/HOOKS=(base udev plymouth autodetect modconf block encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf || \
       ! mkinitcpio -p linux; then
        log_error "Failed to update initramfs" $?
        exit 1
    fi
}

# --- Create User Account ---
create_user() {
    echo -ne "
    #---------------#
    # Creating User #
    #---------------#
    "
    local username="$1"
    log_info "Creating user: $username"
    if ! useradd -m -G wheel,power,storage,uucp,network -s /bin/bash "$username"; then
        log_error "Failed to create user" $?
        exit 1
    fi
}

# --- Set user and root passwords ---
set_passwords() {
    echo -ne "
    #-------------------#
    # Setting Passwords #
    #-------------------#
    "
    log_info "Setting passwords..."
    if ! echo "$USERNAME:$USER_PASSWORD" | chpasswd || \
       ! echo "root:$ROOT_PASSWORD" | chpasswd; then
        log_error "Failed to set passwords" $?
        exit 1
    fi
}

# --- Set hostname ---
set_hostname() {
    echo -ne "
    #------------------#
    # Setting hostname #
    #------------------#
    "
    local hostname="$1"
    log_info "Setting hostname: $hostname"
    if ! echo "$hostname" > /etc/hostname; then 
        log_error "Failed to set hostname" $?
        exit 1
    fi
}

# --- Update sudoers file ---
update_sudoers() {
    echo -ne "
    #------------------#
    # Updating sudoers #
    #------------------#
    "
    log_info "Updating sudoers..."
    if ! cp /etc/sudoers /etc/sudoers.backup || \
       ! sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || \
       ! echo 'Defaults targetpw' >> /etc/sudoers || \
       ! visudo -c; then
        log_error "Failed to update sudoers" $?
        # Restore backup if visudo fails
        cp /etc/sudoers.backup /etc/sudoers
        exit 1
    fi
}

# --- Install GRUB ---
install_grub() {
  echo -ne "
  #-----------------#
  # Installing GRUB #
  #-----------------#
  "
  log_info "Installing GRUB..."
  if ! grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck; then
    log_error "Failed to install GRUB" $?
    exit 1
  fi
}

# --- Install selected GRUB theme ---
install_grub_themes() {
  echo -ne "
  #-----------------------#
  # Installing GRUB Theme #
  #-----------------------#
  "
  log_info "Installing GRUB themes..."

  mkdir -p grub-themes

  case "$GRUB_THEME" in
    poly-dark)
      git clone https://github.com/shvchk/poly-dark.git ./grub-themes/poly-dark
      mv ./grub-themes/poly-dark /boot/grub/themes/
      sed -i 's|^#GRUB_THEME="/path/to/gfxtheme"|GRUB_THEME="/boot/grub/themes/poly-dark/theme.txt"|' /etc/default/grub
      ;;
    CyberEXS)
      git clone https://github.com/HenriqueLopes42/themeGrub.CyberEXS.git ./grub-themes/themeGrub.CyberEXS 
      mv ./grub-themes/themeGrub.CyberEXS /boot/grub/themes/
      sed -i 's|^#GRUB_THEME="/path/to/gfxtheme"|GRUB_THEME="/boot/grub/themes/themeGrub.CyberEXS/theme.txt"|' /etc/default/grub
      ;;
    Cyberpunk)
      git clone https://gitlab.com/anoopmsivadas/Cyberpunk-GRUB-Theme.git ./grub-themes/Cyberpunk-GRUB-Theme 
      mv ./grub-themes/Cyberpunk-GRUB-Theme /boot/grub/themes/
      sed -i 's|^#GRUB_THEME="/path/to/gfxtheme"|GRUB_THEME="/boot/grub/themes/Cyberpunk-GRUB-Theme/Cyberpunk/theme.txt"|' /etc/default/grub
      ;;
    HyperFluent)
      git clone https://github.com/Coopydood/HyperFluent-GRUB-Theme.git ./grub-themes/HyperFluent-GRUB-Theme 
      mv ./grub-themes/HyperFluent-GRUB-Theme /boot/grub/themes/
      sed -i 's|^#GRUB_THEME="/path/to/gfxtheme"|GRUB_THEME="/boot/grub/themes/HyperFluent-GRUB-Theme/arch/theme.txt"|' /etc/default/grub
      ;;
    *)
      log_error "Invalid GRUB Theme specified"
      exit 1
      ;;
  esac

  # Give user ownership of the themes directory
  if ! chown -R $USERNAME:$USERNAME /boot/grub/themes; then 
    log_error "Failed to change ownership of GRUB themes directory"
    exit 1  
  fi
}

# --- Update /etc/default/grub / Run grub-mkconfig ---
configure_grub() {
  echo -ne "
  #------------------#
  # Configuring GRUB #
  #------------------#
  "
  log_info "Configuring GRUB..."

  # Make sure DISK is exported and available in the environment
  if [[ $DISK == "/dev/nvme"* ]]; then
    PART_PREFIX="p"
  else
    PART_PREFIX=""
  fi

  ENCRYPTED_PARTITION="${DISK}${PART_PREFIX}3"
  CRYPT_UUID=$(blkid -s UUID -o value "${ENCRYPTED_PARTITION}")
  ROOT_UUID=$(blkid -s UUID -o value /dev/volgroup0/lv_root)

  if [[ -z $CRYPT_UUID || -z $ROOT_UUID ]]; then
    log_error "Failed to retrieve UUID's for cryptdevice or root partition"
    exit 1
  fi

  sed -i '/^GRUB_DEFAULT=/c\GRUB_DEFAULT=saved' /etc/default/grub 
  sed -i '/^GRUB_TIMEOUT=5/c\GRUB_TIMEOUT=3' /etc/default/grub 
  sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet splash cryptdevice=UUID='${CRYPT_UUID}':volgroup0 root=UUID='${ROOT_UUID}' loglevel=3"' /etc/default/grub 
  sed -i '/^#GRUB_ENABLE_CRYPTODISK=y/c\GRUB_ENABLE_CRYPTODISK=y' /etc/default/grub 
  sed -i '/^GRUB_GFXMODE=auto/c\GRUB_GFXMODE=1280x1024x32,auto' /etc/default/grub 
  sed -i '/^#GRUB_SAVEDEFAULT=true/c\GRUB_SAVEDEFAULT=true' /etc/default/grub 

  if ! cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale.en.mo || \
     ! grub-mkconfig -o /boot/grub/grub.cfg; then
    log_error "Failed to configure GRUB" $?
    exit 1
  fi
}

install_gpu_drivers() {
  echo -ne "
  #---------------------------#
  # Detect/Install GPU Drivers#
  #---------------------------#
  "
  log_info "Detecting GPUs..."

  # Detect GPUs (both NVIDIA and AMD)
  readarray -t gpus < <(lspci -k | grep -E "(VGA|3D)")

  if [[ ${#gpus[@]} -eq 0 ]]; then
    log_info "No GPUs detected. Skipping driver installation."
    return 0
  fi

  for gpu in "${gpus[@]}"; do
    vendor=$(echo "$gpu" | grep -oE "(NVIDIA|AMD|Radeon|Vulkan)" | head -n 1)

    if [[ "$vendor" == "NVIDIA" ]]; then
      log_info "NVIDIA GPU detected:"
      log_info "$gpu"

      log_info "Installing NVIDIA drivers..."
      if ! pacman -S --noconfirm --needed nvidia libglvnd nvidia-utils opencl-nvidia lib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia nvidia-settings; then
        log_error "Failed to install NVIDIA packages" $?
        return 1
      fi

      log_info "Updating initramfs..."
      if ! sed -i '/^MODULES=()/c\MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' /etc/mkinitcpio.conf || \
       ! mkinitcpio -p linux; then
        log_error "Failed to update initramfs with NVIDIA modules" $?
        return 1
      fi

      log_info "Updating GRUB configuration..."

      # Make sure DISK is exported and available in the environment
      if [[ $DISK == "/dev/nvme"* ]]; then
        PART_PREFIX="p"
      else
        PART_PREFIX=""
      fi

      ENCRYPTED_PARTITION="${DISK}${PART_PREFIX}3"
      CRYPT_UUID=$(blkid -s UUID -o value "${ENCRYPTED_PARTITION}")
      ROOT_UUID=$(blkid -s UUID -o value /dev/volgroup0/lv_root)

      if [[ -z $CRYPT_UUID || -z $ROOT_UUID ]]; then
        log_error "Failed to retrieve UUID's for cryptdevice or root partition"
        return 1 # Indicate failure
      fi

      if ! sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="quiet splash cryptdevice=UUID='"${CRYPT_UUID}"':volgroup0 root=UUID='"${ROOT_UUID}"' loglevel=3"|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash cryptdevice=UUID='"${CRYPT_UUID}"':volgroup0 root=UUID='"${ROOT_UUID}"' nvidia_drm_modeset=1 loglevel=3"|' /etc/default/grub || \
       ! grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Failed to update GRUB configuration with NVIDIA settings" $?
        return 1
      fi

      log_info "NVIDIA drivers installed and configured successfully."
      return 0

    elif [[ "$vendor" == "AMD" || "$vendor" == "Radeon" || "$vendor" == "Vulkan" ]]; then
      log_info "AMD Radeon GPU detected:"
      log_info "$gpu"

      log_info "Installing Radeon drivers and related packages..."
      if ! pacman -S --noconfirm --needed mesa mesa-utils amdgpu amdgpu-firmware vulkan-radeon xf86-video-amdgpu lib32-mesa lib32-vulkan-radeon; then
        log_error "Failed to install Radeon packages" $?
        return 1
      fi

      # Check for amdgpu kernel module *only if a GPU was detected*
      if ! lsmod | grep amdgpu; then
        log_warn "amdgpu kernel module not loaded. Reboot may be required."
      fi

      log_info "Radeon drivers and related packages installed successfully."
      return 0

    fi
  done
}

install_gui() {
    echo -ne "
    #---------------------------#
    # Installing Server/Desktop #
    #---------------------------#
    "

    if [[ "$GUI_CHOICE" == "hyprland" ]]; then
        # Clone the dotfiles branch
        git clone --progress --verbose https://github.com/live4thamuzik/L4TM-HyDE.git /home/$USERNAME/L4TM-HyDE || {
            log_error "Failed to clone L4TM-HyDE"
            exit 1
        }

        #Fix permissions
        chown $USERNAME /home/$USERNAME/L4TM-HyDE
        chmod -R 777 /home/$USERNAME/L4TM-HyDE

        # Copy Configs to /
        cd /home/$USERNAME/L4TM-HyDE/Scripts

        # Temporarily allow the user to run sudo without a password (within the chroot)
        echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null

        # Switch to the created user and install HyDE
        if ! runuser -u "$USERNAME" -- /bin/bash -c '
            # Call hypr.sh
            if ! bash ./install.sh; then
                log_error "Failed to install HyDE" "$?"
                exit 1
            fi
        '; then
            log_error "Failed to install AUR packages as $USERNAME" "$?"
            # Remove the temporary sudoers entry in case of failure
            sed -i "/$USERNAME ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers
            exit 1
        fi

        # Remove the temporary sudoers entry
        sed -i "/$USERNAME ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers

        log_info "HyDE installation complete!"

    elif [[ "$GUI_CHOICE" == "gnome" ]]; then
        log_info "Installing GNOME desktop environment..."

        if ! pacman -S --noconfirm --needed gnome gnome-extra gnome-tweaks gnome-shell-extensions gnome-browser-connector firefox; then
            log_error "Failed to install GNOME packages: $?"
            exit 1
        fi

        if ! systemctl enable gdm.service; then
            log_error "Failed to enable gdm service: $?"
            exit 1
        fi

        log_info "GNOME installed and gdm enabled."

    elif [[ "$GUI_CHOICE" == "kde" ]]; then
        log_info "Installing KDE Plasma desktop environment..."

        if ! pacman -S --noconfirm --needed xorg plasma-desktop sddm kde-applications dolphin firefox lxappearance; then
            log_error "Failed to install KDE Plasma packages: $?"
            exit 1
        fi

        if ! systemctl enable sddm.service; then
            log_error "Failed to enable sddm service: $?"
            exit 1
        fi

        log_info "KDE Plasma installed and sddm enabled."

    else
        log_info "No GUI selected. Skipping GUI installation."
    fi
}

# --- Install selected AUR Helper ---
install_aur_helper() {
    echo -ne "
    #-----------------------#
    # Installing AUR Helper #
    #-----------------------#
    "
    log_info "Installing AUR helper..."

     # Temporarily allow the user to run sudo without a password
     echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Switch to the created user
    if ! runuser -u "$USERNAME" -- /bin/bash -c "
        # Install git if not already installed
        if ! pacman -Qi git &> /dev/null; then
            if ! sudo pacman -S --noconfirm git; then
                log_error \"Failed to install git\" 3
                exit 3
            fi
        fi

        # Install the chosen AUR helper
        case \"$AUR_HELPER\" in
            yay)
                mkdir -p tmp
                cd tmp && git clone https://aur.archlinux.org/yay.git || { log_error \"Failed to clone yay repository\" 4; exit 4; }
                cd yay && makepkg -si --noconfirm -C yay || { log_error \"Failed to build and install yay\" 5; exit 5; }
                ;;
            paru)
                mkdir -p tmp
                cd tmp && git clone https://aur.archlinux.org/paru.git || { log_error \"Failed to clone paru repository\" 6; exit 6; }
                cd paru && makepkg -si --noconfirm -C paru || { log_error \"Failed to build and install paru\" 7; exit 7; }
                ;;
            *)
                log_error \"Invalid AUR helper specified\" 8
                exit 8
                ;;
        esac
    "; then
        log_error "Failed to switch to user" 9
        return 9
    fi

    # Remove the temporary sudoers entry
    sed -i "/$USERNAME ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers

    log_info "AUR helper installed."
}

install_aur_pkgs() {
    echo -ne "
    #------------------------#
    # Installing AUR Packages #
    #------------------------#
    "
    log_info "Installing AUR packages..."

    # Temporarily allow the user to run sudo without a password
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    # Switch to the created user and install AUR packages
    if ! runuser -u "$USERNAME" -- /bin/bash -c "
        # Check if the AUR helper is installed
        if ! command -v \"$AUR_HELPER\" &> /dev/null; then
            log_error \"AUR helper '$AUR_HELPER' not found. Make sure it's installed.\" 1
            exit 1
        fi

        # Install AUR packages using paru
        if ! paru -S --noconfirm --needed - < ./aur_pkgs.lst; then
            log_error \"Failed to install AUR packages\" \$?
            exit 1
        fi
    "; then
        log_error "Failed to install AUR packages as $USERNAME" $?
        # Remove the temporary sudoers entry in case of failure
        sed -i "/$USERNAME ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers
        exit 1
    fi

    # Remove the temporary sudoers entry
    sed -i "/$USERNAME ALL=(ALL) NOPASSWD: ALL/d" /etc/sudoers
}

# --- Add HOOKS to mkinitcpoio.conf for numlock on boot / Update initramfs --- 
numlock_auto_on() {
    echo -ne "
    #--------------------#
    # Updating Initramfs #
    #--------------------#
    "
    log_info "Updating initramfs..."
    if ! sed -i 's/^HOOKS\s*=\s*(.*)/HOOKS=(base udev plymouth autodetect modconf numlock block encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf || \
       ! mkinitcpio -p linux; then
        log_error "Failed to update initramfs" $?
        exit 1
    fi
}

# --- Cleanup Function ---
cleanup() {
    log_info "Cleaning up..."

    # Remove temporary files and directories created during the installation
    rm -rf /mnt/global_functions.sh
    rm -rf /mnt/chroot.sh
    rm -rf /mnt/pkgs.lst
    rm -rf /mnt/aur_pkgs.lst
    rm -rf /mnt/tmp
    rm -rf /mnt/grub-themes

    # Copy log files to the installed system
    cp /var/log/archl4tm.log /mnt/var/log/archl4tm.log
    cp /var/log/archl4tm_error.log /mnt/var/log/archl4tm_error.log
}
