// Lethal Company Takeover: the facility is dark and foggy, every monster drops scrap worth money,
// the player has a flashlight and a quota to meet, Hoarding Bugs steal scrap from the floor and
// Brackens stalk the halls. Dogs of the map are Hoarding Bugs, knights are Brackens.

entity() SIGF_Anchor;
float sigf_total;       // money collected
float sigf_quota;       // current quota
float sigf_met;         // quotas met so far
.float sigf_init;
.float sigf_value;      // scrap value
.float sigf_carry;      // scrap value a bug is carrying
.float sigf_hint_at;
.float sigf_strobe_until;
.float sigf_strobe_next;
.float sigf_strobe_on;
.float sigf_spawn_at;

// ---------- scrap: loot that pops out of every monster ----------
string(float v) sigf_scrap_name =
{
    if (v < 70)
        return "Rubber Duck";
    if (v < 120)
        return "Brass Bell";
    return "Cash Register";
};

void(float v) sigf_quota_bar =
{
    local float t;
    t = floor(sigf_total * 10 / sigf_quota);
    if (t <= 0) centerprint(self, "QUOTA  [..........]\n");
    else if (t == 1) centerprint(self, "QUOTA  [#.........]\n");
    else if (t == 2) centerprint(self, "QUOTA  [##........]\n");
    else if (t == 3) centerprint(self, "QUOTA  [###.......]\n");
    else if (t == 4) centerprint(self, "QUOTA  [####......]\n");
    else if (t == 5) centerprint(self, "QUOTA  [#####.....]\n");
    else if (t == 6) centerprint(self, "QUOTA  [######....]\n");
    else if (t == 7) centerprint(self, "QUOTA  [#######...]\n");
    else if (t == 8) centerprint(self, "QUOTA  [########..]\n");
    else centerprint(self, "QUOTA  [#########.]\n");
};

void() sigf_quota_met =
{
    sigf_met = sigf_met + 1;
    sigf_quota = sigf_quota + 400;
    sound(self, CHAN_VOICE, "sigf/horn.wav", 1, ATTN_NONE);
    centerprint(self, "\n\n*** QUOTA MET ***\n\nTHE COMPANY IS PLEASED\n\nNew quota assigned. Quad Damage!\n");
    self.sigf_strobe_until = time + 3;
    bprint("The Company is pleased. A bigger quota is set.\n");
    self.items = self.items | IT_QUAD;
    self.super_damage_finished = time + 10;
    self.super_time = 1;
    particle(self.origin, '0 0 120', 192, 250);
    particle(self.origin, '0 0 80', 232, 120);
    WriteByte(MSG_BROADCAST, SVC_TEMPENTITY);
    WriteByte(MSG_BROADCAST, TE_TELEPORT);
    WriteCoord(MSG_BROADCAST, self.origin_x);
    WriteCoord(MSG_BROADCAST, self.origin_y);
    WriteCoord(MSG_BROADCAST, self.origin_z);
};

void() sigf_scrap_touch =
{
    local entity oldself;
    if (other.classname != "player")
        return;
    sigf_total = sigf_total + self.sigf_value;
    sound(other, CHAN_ITEM, "sigf/cash.wav", 1, ATTN_NORM);
    stuffcmd(other, "bf\n");
    oldself = self;
    self = other;
    sprint(self, "+$");
    sprint(self, ftos(oldself.sigf_value));
    sprint(self, " ");
    sprint(self, sigf_scrap_name(oldself.sigf_value));
    sprint(self, "   Total $");
    sprint(self, ftos(sigf_total));
    sprint(self, " / $");
    sprint(self, ftos(sigf_quota));
    sprint(self, "\n");
    if (sigf_total >= sigf_quota)
        sigf_quota_met();
    else
        sigf_quota_bar(0);
    self = oldself;
    remove(self);
};

// scrap flies to a near player, and a Hoarding Bug that reaches it steals it
void() sigf_scrap_think =
{
    local entity e, p;
    self.nextthink = time + 0.1;
    if (self.sigf_hint_at < time - 40)
    {
        remove(self);
        return;
    }
    e = findradius(self.origin, 44);
    while (e)
    {
        if (e.classname == "monster_sigf_bug" && e.health > 0)
        {
            e.sigf_carry = e.sigf_carry + self.sigf_value;
            e.effects = e.effects | EF_BRIGHTLIGHT;
            sound(e, CHAN_ITEM, "sigf/chitter.wav", 1, ATTN_NORM);
            particle(self.origin, '0 0 40', 192, 30);
            p = find(world, classname, "player");
            if (p)
                sprint(p, "A Hoarding Bug stole the scrap! Kill it to get it back.\n");
            remove(self);
            return;
        }
        e = e.chain;
    }
    p = find(world, classname, "player");
    if (p && self.flags & FL_ONGROUND && vlen(p.origin - self.origin) < 110 && time > self.sigf_hint_at + 1.5)
    {
        self.velocity = normalize(p.origin - self.origin) * 260;
        self.velocity_z = self.velocity_z + 60;
        self.flags = self.flags - FL_ONGROUND;
    }
};

void(vector org, float v) sigf_drop_scrap =
{
    local entity o;
    o = spawn();
    o.classname = "sigf_scrap";
    o.movetype = MOVETYPE_TOSS;
    o.solid = SOLID_TRIGGER;
    o.sigf_value = floor(v);
    o.sigf_hint_at = time;
    setmodel(o, "progs/sigf_scrap.spr");
    if (v < 70)
        o.frame = 0;
    else if (v < 120)
        o.frame = 1;
    else
        o.frame = 2;
    setsize(o, '-20 -20 0', '20 20 48');
    setorigin(o, org + '0 0 12');
    o.velocity_x = crandom() * 140;
    o.velocity_y = crandom() * 140;
    o.velocity_z = 260 + random() * 100;
    o.effects = EF_DIMLIGHT;
    o.touch = sigf_scrap_touch;
    o.think = sigf_scrap_think;
    o.nextthink = time + 0.5;
    sound(o, CHAN_ITEM, "weapons/lock4.wav", 0.6, ATTN_NORM);
};

// Spawns a monster in the most open direction around the player (never inside a wall), facing the player.
void(string cls, void() spawnfunc, float dist) sigf_spawn_open =
{
    local entity p, e, oself;
    local float i, yaw, bestyaw, bestlen, len;
    local vector start, org;
    p = SIGF_Anchor();
    if (!p)
        return;
    start = p.origin + '0 0 16';
    bestlen = 0;
    bestyaw = 0;
    i = 0;
    while (i < 12)
    {
        yaw = p.v_angle_y + i * 30 + crandom() * 10;
        makevectors('0 1 0' * yaw);
        traceline(start, start + v_forward * 600, TRUE, p);
        len = vlen(trace_endpos - start);
        if (i == 0 || i == 1 || i == 11)
            len = len * 1.3;                 // prefer what the player already looks at
        if (len > bestlen)
        {
            bestlen = len;
            bestyaw = yaw;
        }
        i = i + 1;
    }
    makevectors('0 1 0' * bestyaw);
    len = bestlen - 60;
    if (len > dist)
        len = dist;
    if (len < 70)
        return;
    org = start + v_forward * len;
    if (pointcontents(org) == CONTENT_SOLID)
        return;
    e = spawn();
    e.classname = cls;
    setorigin(e, org);
    e.angles_y = bestyaw + 180;
    oself = self;
    self = e;
    spawnfunc();
    self = oself;
};

// ---------- player: flashlight, fog, quota ----------
void() SIGF_LCPlayer =
{
    local entity e;
    local float n;
    if (!self.sigf_init)
    {
        self.sigf_init = 1;
        sigf_quota = 600;
        lightstyle(0, "j");
        stuffcmd(self, "fog 0.2 0.12 0.09 0.05\n");
        centerprint(self, "\n\nLETHAL COMPANY\n\nCollect scrap. Meet the quota.\nWatch out for the Bracken!\n");
        stuffcmd(self, "bf\n");
        self.sigf_hint_at = time + 7;
    }
    self.effects = self.effects | EF_DIMLIGHT;     // the flashlight
    if (self.sigf_strobe_until > time)
    {
        // alarm: the whole facility strobes and the screen flashes
        if (self.sigf_strobe_next < time)
        {
            self.sigf_strobe_next = time + 0.18;
            self.sigf_strobe_on = 1 - self.sigf_strobe_on;
            if (self.sigf_strobe_on)
            {
                lightstyle(0, "z");
                stuffcmd(self, "bf\n");
            }
            else
                lightstyle(0, "b");
        }
    }
    else if (self.sigf_strobe_until)
    {
        self.sigf_strobe_until = 0;
        lightstyle(0, "j");
    }
    if (SIGF_Mode() == 1 && self.sigf_spawn_at < time && time > 4)
    {
        // demo: keep the facility crawling with monsters around the player
        self.sigf_spawn_at = time + 1.2;
        n = 0;
        e = find(world, classname, "monster_sigf_bug");
        while (e) { if (e.health > 0) n = n + 1; e = find(e, classname, "monster_sigf_bug"); }
        e = find(world, classname, "monster_sigf_bracken");
        while (e) { if (e.health > 0) n = n + 2; e = find(e, classname, "monster_sigf_bracken"); }
        if (n < 6)
        {
            if (random() < 0.4)
                sigf_spawn_open("monster_sigf_bracken", monster_sigf_bracken, 200 + random() * 60);
            else
                sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 160 + random() * 80);
        }
    }
    if (self.sigf_hint_at && self.sigf_hint_at < time)
    {
        self.sigf_hint_at = time + 10;
        sigf_quota_bar(0);
    }
};

// ---------- shared melee ----------
void(float dmg, float reach) sigf_bite =
{
    if (!self.enemy)
        return;
    ai_face();
    if (vlen(self.enemy.origin - self.origin) > reach)
        return;
    T_Damage(self.enemy, self, self, dmg);
    sound(self, CHAN_WEAPON, "sigf/hurt.wav", 1, ATTN_NORM);
    particle(self.enemy.origin, '0 0 30', 64, 40);
};

void() sigf_pain_sparks =
{
    particle(self.origin + '0 0 8', '0 0 40', 232, 25);
};

// ---------- Hoarding Bug: fast, small, steals scrap ----------
void() bug_stand1 = [0, bug_stand2] { ai_stand(); };
void() bug_stand2 = [1, bug_stand1] { ai_stand(); };
void() bug_walk1 = [2, bug_walk2] { ai_walk(8); };
void() bug_walk2 = [3, bug_walk3] { ai_walk(8); };
void() bug_walk3 = [4, bug_walk4] { ai_walk(8); };
void() bug_walk4 = [5, bug_walk1] { ai_walk(8); };
void() bug_run1 = [2, bug_run2] { ai_run(22); };
void() bug_run2 = [3, bug_run3] { ai_run(22); };
void() bug_run3 = [4, bug_run4] { ai_run(22); };
void() bug_run4 = [5, bug_run1] { ai_run(22); };

void() bug_atk1 = [6, bug_atk2] { ai_face(); sound(self, CHAN_VOICE, "sigf/chitter.wav", 1, ATTN_NORM); };
void() bug_atk2 = [7, bug_atk3] { ai_charge(14); };
void() bug_atk3 = [8, bug_atk4] { ai_charge(14); sigf_bite(8, 70); };
void() bug_atk4 = [9, bug_run1] { ai_charge(6); };

void() bug_pain1 = [10, bug_pain2] { sigf_pain_sparks(); };
void() bug_pain2 = [11, bug_run1] { };
void(entity attacker, float damage) bug_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 0.6;
    sound(self, CHAN_VOICE, "sigf/hurt.wav", 1, ATTN_NORM);
    bug_pain1();
};

void() bug_die1 = [12, bug_die2] { };
void() bug_die2 = [13, bug_die3] { self.solid = SOLID_NOT; };
void() bug_die3 = [14, bug_die4] { };
void() bug_die4 = [15, bug_die5] { };
void() bug_die5 = [16, bug_die5] { };

void() bug_die =
{
    sigf_drop_scrap(self.origin, 25 + floor(random() * 25));
    if (self.sigf_carry > 0)
        sigf_drop_scrap(self.origin, self.sigf_carry);   // scrap the bug stole comes back
    if (self.health < -30)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        ThrowHead("progs/gib3.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "sigf/chitter.wav", 1, ATTN_NORM);
    bug_die1();
};

void() monster_sigf_bug =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_bug.mdl");
    precache_model("progs/sigf_scrap.spr");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    precache_sound("sigf/chitter.wav");
    precache_sound("sigf/hurt.wav");
    precache_sound("sigf/cash.wav");
    precache_sound("sigf/horn.wav");
    precache_sound("weapons/lock4.wav");
    precache_sound("player/udeath.wav");
    self.classname = "monster_sigf_bug";
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_bug.mdl");
    setsize(self, '-24 -24 -24', '24 24 20');
    self.health = 110;                      // a dog has 25, a grunt 30
    self.sigf_carry = 0;
    self.th_stand = bug_stand1;
    self.th_walk = bug_walk1;
    self.th_run = bug_run1;
    self.th_melee = bug_atk1;
    self.th_pain = bug_pain;
    self.th_die = bug_die;
    walkmonster_start();
};

// ---------- Bracken: tall, silent, snaps necks ----------
void() bracken_stand1 = [0, bracken_stand2] { ai_stand(); };
void() bracken_stand2 = [1, bracken_stand1] { ai_stand(); };
void() bracken_walk1 = [2, bracken_walk2] { ai_walk(6); };
void() bracken_walk2 = [3, bracken_walk3] { ai_walk(6); };
void() bracken_walk3 = [4, bracken_walk4] { ai_walk(6); };
void() bracken_walk4 = [5, bracken_walk1] { ai_walk(6); };
void() bracken_run1 = [2, bracken_run2] { ai_run(16); };
void() bracken_run2 = [3, bracken_run3] { ai_run(16); };
void() bracken_run3 = [4, bracken_run4] { ai_run(16); };
void() bracken_run4 = [5, bracken_run1] { ai_run(16); };

void() bracken_atk1 = [6, bracken_atk2] { ai_face(); sound(self, CHAN_VOICE, "sigf/growl.wav", 1, ATTN_NORM); };
void() bracken_atk2 = [7, bracken_atk3] { ai_charge(10); };
void() bracken_atk3 = [8, bracken_atk4] { ai_charge(10); sigf_bite(22, 90); };
void() bracken_atk4 = [9, bracken_run1] { ai_charge(4); };

void() bracken_pain1 = [10, bracken_pain2] { sigf_pain_sparks(); };
void() bracken_pain2 = [11, bracken_run1] { };
void(entity attacker, float damage) bracken_pain =
{
    if (self.pain_finished > time)
        return;
    self.pain_finished = time + 1;
    sound(self, CHAN_VOICE, "sigf/hurt.wav", 1, ATTN_NORM);
    bracken_pain1();
};

void() bracken_die1 = [12, bracken_die2] { };
void() bracken_die2 = [13, bracken_die3] { self.solid = SOLID_NOT; };
void() bracken_die3 = [14, bracken_die4] { };
void() bracken_die4 = [15, bracken_die5] { };
void() bracken_die5 = [16, bracken_die5] { };

void() bracken_die =
{
    sigf_drop_scrap(self.origin, 130 + random() * 60);   // a Bracken pays well
    sigf_drop_scrap(self.origin, 90 + random() * 30);
    if (self.health < -40)
    {
        sound(self, CHAN_VOICE, "player/udeath.wav", 1, ATTN_NORM);
        ThrowGib("progs/gib1.mdl", self.health);
        ThrowGib("progs/gib2.mdl", self.health);
        ThrowHead("progs/gib3.mdl", self.health);
        return;
    }
    sound(self, CHAN_VOICE, "sigf/growl.wav", 1, ATTN_NORM);
    bracken_die1();
};

void() monster_sigf_bracken =
{
    if (deathmatch)
    {
        remove(self);
        return;
    }
    precache_model("progs/sigf_bracken.mdl");
    precache_model("progs/sigf_scrap.spr");
    precache_model("progs/gib1.mdl");
    precache_model("progs/gib2.mdl");
    precache_model("progs/gib3.mdl");
    precache_sound("sigf/growl.wav");
    precache_sound("sigf/hurt.wav");
    precache_sound("sigf/cash.wav");
    precache_sound("sigf/horn.wav");
    precache_sound("weapons/lock4.wav");
    precache_sound("player/udeath.wav");
    self.classname = "monster_sigf_bracken";
    self.solid = SOLID_SLIDEBOX;
    self.movetype = MOVETYPE_STEP;
    setmodel(self, "progs/sigf_bracken.mdl");
    setsize(self, '-18 -18 -24', '18 18 72');
    self.health = 260;                      // a knight has 75, an ogre 200
    self.th_stand = bracken_stand1;
    self.th_walk = bracken_walk1;
    self.th_run = bracken_run1;
    self.th_melee = bracken_atk1;
    self.th_pain = bracken_pain;
    self.th_die = bracken_die;
    walkmonster_start();
};

// ---------- hooks ----------
void() SIGF_Precache =
{
    precache_model("progs/sigf_scrap.spr");
    precache_sound("sigf/horn.wav");
    precache_sound("sigf/cash.wav");
    precache_sound("weapons/lock4.wav");
    precache_sound("items/damage2.wav");
    SIGF_Preload("monster_sigf_bug", monster_sigf_bug);
    SIGF_Preload("monster_sigf_bracken", monster_sigf_bracken);
    SIGF_Preload("monster_ogre", monster_ogre);
};

void(float wave) SIGF_DemoWave =
{
    if (wave == 0)
    {
        self.items = self.items | IT_SUPER_SHOTGUN | IT_NAILGUN | IT_SUPER_NAILGUN | IT_ROCKET_LAUNCHER;
        self.weapon = IT_NAILGUN;
        W_SetCurrentAmmo();
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 100);
        sigf_spawn_open("monster_sigf_bracken", monster_sigf_bracken, 130);
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 115);
        return;
    }
    if (wave & 1)
    {
        sigf_spawn_open("monster_sigf_bracken", monster_sigf_bracken, 210);
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 170);
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 160);
    }
    else
    {
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 160);
        sigf_spawn_open("monster_sigf_bug", monster_sigf_bug, 180);
        sigf_spawn_open("monster_sigf_bracken", monster_sigf_bracken, 230);
    }
};

void(entity targ, entity attacker) SIGF_OnKilled =
{
    local float v;
    if (!(targ.flags & FL_MONSTER))
        return;
    if (targ.classname == "monster_sigf_bug" || targ.classname == "monster_sigf_bracken")
        return;                                   // their death code drops their own scrap
    v = 25 + targ.max_health * 0.4 + random() * 30;
    sigf_drop_scrap(targ.origin, floor(v));
};
