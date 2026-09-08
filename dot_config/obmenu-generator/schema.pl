#!/usr/bin/env perl

# obmenu-generator — схема меню Openbox (правый клик по рабочему столу).
# За основу взята схема из dotfiles owl4ce; пункты механизма joyful-desktop удалены,
# иконки — по именам из темы значков.

=for comment

    item:      add an item inside the menu               {item => ["command", "label", "icon"]},
    cat:       add a category inside the menu             {cat => ["name", "label", "icon"]},
    sep:       horizontal line separator                  {sep => undef}, {sep => "label"},
    pipe:      a pipe menu entry                         {pipe => ["command", "label", "icon"]},
    file:      include the content of an XML file        {file => "/path/to/file.xml"},
    raw:       any XML data supported by Openbox          {raw => q(...)},
    beg:       begin of a category                        {beg => ["name", "icon"]},
    end:       end of a category                          {end => undef},
    obgenmenu: generic menu settings                {obgenmenu => ["label", "icon"]},
    exit:      default "Exit" action                     {exit => ["label", "icon"]},

=cut

# NOTE:
#    * Keys and values are case sensitive. Keep all keys lowercase.
#    * ICON can be a either a direct path to an icon or a valid icon name
#    * Category names are case insensitive. (X-XFCE and x_xfce are equivalent)

require "$ENV{HOME}/.config/obmenu-generator/config.pl";

# Text editor
my $editor = $CONFIG->{editor};

our $SCHEMA = [
    {sep       => "QUICK START"},

    #              COMMAND                                                              LABEL                          ICON
    {beg       => [                                                                     "Launch Apps",                 "system-search"]},
    {cat       => ["utility",                                                           "Accessories",                 "applications-utilities"]},
    {cat       => ["development",                                                       "Development",                 "applications-development"]},
    {cat       => ["education",                                                         "Education",                   "applications-science"]},
    {cat       => ["game",                                                              "Games",                       "applications-games"]},
    {cat       => ["graphics",                                                          "Graphics",                    "applications-graphics"]},
    {cat       => ["audiovideo",                                                        "Multimedia",                  "applications-multimedia"]},
    {cat       => ["network",                                                           "Network",                     "applications-internet"]},
    {cat       => ["office",                                                            "Office",                      "applications-office"]},
    {cat       => ["other",                                                             "Other",                       "applications-other"]},
    {cat       => ["settings",                                                          "Settings",                    "applications-accessories"]},
    {cat       => ["system",                                                            "System",                      "applications-system"]},
    {end       => undef},

    {sep       => undef},

    {item      => ["wezterm-gui",                                                        "Open Terminal",               "utilities-terminal"]},
    {item      => ["thunar",                                                             "Open File Manager",           "system-file-manager"]},

    {sep       => undef},

    {beg       => [                                                                     "Screenshot",                  "camera-photo"]},
    {item      => ["$ENV{HOME}/.scripts/screenshot-screen.sh delay",                    "Screen",                      "camera-photo"]},
    {item      => ["$ENV{HOME}/.scripts/screenshot-selection.sh",                       "Select or Draw",              "camera-photo"]},
    {item      => ["$ENV{HOME}/.scripts/screenshot-countdown.sh",                       "Countdown ?s",                "camera-photo"]},
    {end       => undef},

    {sep       => undef},

    {pipe      => ["$ENV{HOME}/.config/openbox/pipe-menu/ob-randr.py",                  "Monitor Settings",            "preferences-desktop-display"]},
    {obgenmenu => [                                                                     "Advanced Settings",           "preferences-system"]},

    {sep       => undef},

    {sep       =>                                                                       "SESSIONS"},

    {item      => ["loginctl --no-ask-password lock-session",                           "Lock",                        "system-lock-screen"]},

    {sep       => undef},

    {exit      => [                                                                     "Exit Openbox",                "system-log-out"]},
]
