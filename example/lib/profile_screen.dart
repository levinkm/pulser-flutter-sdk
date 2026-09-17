import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final String userId;

  const ProfileScreen({
    super.key,
    required this.name,
    required this.userId,
    this.avatarUrl,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _titleVisible = false;

  // The expanded height of the flexible space (avatar + name area)
  static const double _expandedHeight = 260.0;
  // Approx point where the name has scrolled out of view
  static const double _collapseThreshold = 160.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > _collapseThreshold;
    if (collapsed != _titleVisible) {
      setState(() => _titleVisible = collapsed);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: _expandedHeight,
            pinned: true,
            stretch: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            // Title fades in only when collapsed
            title: AnimatedOpacity(
              opacity: _titleVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                children: [
                  _Avatar(
                    name: widget.name,
                    avatarUrl: widget.avatarUrl,
                    radius: 16,
                    fontSize: 13,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              // Hide the built-in title — we handle it above
              titlePadding: EdgeInsets.zero,
              stretchModes: const [StretchMode.zoomBackground],
              background: _ExpandedHeader(
                name: widget.name,
                avatarUrl: widget.avatarUrl,
                userId: widget.userId,
              ),
            ),
          ),

          // Profile detail rows
          SliverList(
            delegate: SliverChildListDelegate([
              _SectionHeader('About'),
              _InfoTile(
                icon: Icons.info_outline,
                label: 'Status',
                value: 'Hey there! I am using this app.',
              ),
              _InfoTile(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: '+1 (555) 000-0000',
              ),
              _InfoTile(
                icon: Icons.badge_outlined,
                label: 'User ID',
                value: widget.userId,
                monospace: true,
              ),
              const Divider(height: 32),
              _SectionHeader('Notifications'),
              _InfoTile(
                icon: Icons.notifications_outlined,
                label: 'Mute notifications',
                value: '',
                trailing: Switch(value: false, onChanged: (_) {}),
              ),
              _InfoTile(
                icon: Icons.inbox_outlined,
                label: 'Inbox',
                value: 'All messages',
              ),
              const Divider(height: 32),
              _SectionHeader('Media'),
              _MediaGrid(),
              const Divider(height: 32),
              // Danger zone
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error.withOpacity(0.4)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.block),
                  label: const Text('Block user'),
                  onPressed: () {},
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Expanded header (visible when scrolled to top) ───────────────────────────

class _ExpandedHeader extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String userId;

  const _ExpandedHeader({
    required this.name,
    required this.userId,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _Avatar(name: name, avatarUrl: avatarUrl, radius: 52, fontSize: 36),
          const SizedBox(height: 12),
          Text(
            name,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            userId,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                  fontFamily: 'monospace',
                ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Reusable avatar (initials fallback) ──────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double radius;
  final double fontSize;

  const _Avatar({
    required this.name,
    required this.radius,
    required this.fontSize,
    this.avatarUrl,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
      child: avatarUrl == null
          ? Text(
              _initials,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ── Info tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool monospace;
  final Widget? trailing;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(label),
      subtitle: value.isNotEmpty
          ? Text(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: 13,
              ),
            )
          : null,
      trailing: trailing,
    );
  }
}

// ── Placeholder media grid ────────────────────────────────────────────────────

class _MediaGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: 6,
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}
