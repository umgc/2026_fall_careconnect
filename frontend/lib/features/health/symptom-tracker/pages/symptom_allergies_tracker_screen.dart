import 'dart:io';

import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_tab.dart';
import 'package:care_connect_app/widgets/default_app_header.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_tab.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';

class SymptomsAllergiesPage extends StatefulWidget {
  const SymptomsAllergiesPage({super.key});

  @override
  State<SymptomsAllergiesPage> createState() => _SymptomsAllergiesPageState();
}

class _SymptomsAllergiesPageState extends State<SymptomsAllergiesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _patientId;
  bool _isResolving = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _resolvePatientId();
  }

  Future<void> _resolvePatientId() async {
    setState(() {
      _isResolving = true;
      _errorMessage = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final pid = userProvider.user?.patientId;

      if (pid == null || pid == 0) {
        setState(() {
          _errorMessage = 'Patient ID not found';
          _isResolving = false;
        });
        return;
      }

      setState(() {
        _patientId = pid.toString();
        _isResolving = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error resolving patient ID: $e';
        _isResolving = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const DefaultAppHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isLandscape =
                      MediaQuery.of(context).orientation == Orientation.landscape;

                  return Container(
                    margin: EdgeInsets.all(isLandscape? 8 : 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(isLandscape? 16 : 32),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .shadowColor
                              .withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isLandscape
                        ? _buildLandscapeLayout()
                        : _buildPortraitLayout(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Portrait: fixed header, only tab content scrolls
  Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildHeader(false),
        _buildTabBar(false),
        Expanded(child: _buildBody()),
      ],
    );
  }

  // Landscape: header + tabs scroll away, reduced header
  Widget _buildLandscapeLayout() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(child: _buildHeader(true)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(_buildTabBar(true)),
          ),
        ];
      },
      body: _buildBody(),
    );
  }

  Widget _buildHeader(bool isLandscape) {
    return Padding(
      padding: EdgeInsets.all(isLandscape? 12 : 20),
      child: Column(
        children: [
          if (!isLandscape)...[
            Icon(
              Icons.medical_information_outlined,
              color: Theme.of(context).primaryColor,
              size: 32,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLandscape)...[
                Icon(
                  Icons.medical_information_outlined,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'Symptoms & Allergies',
                style: TextStyle(
                  fontSize: isLandscape? 18 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          if (!isLandscape)...[
            const SizedBox(height: 8),
            Text(
              'Track your health symptoms and medication allergies',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isLandscape) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: EdgeInsets.fromLTRB(20, 0, 20, isLandscape? 8 : 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(10),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isLandscape? 12 : 14,
          ),
          tabs: const [
            Tab(text: 'Mental Health\nSymptoms'),
            Tab(text: 'Drug Allergies'),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isResolving) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage!= null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _resolvePatientId,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_patientId!= null) {
      return TabBarView(
        controller: _tabController,
        children: [
          SymptomTab(patientId: _patientId!),
          AllergiesTab(patientId: _patientId!),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar);

  final Widget _tabBar;

  @override
  double get minExtent => 56; // Approximate TabBar height
  @override
  double get maxExtent => 56;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _tabBar;
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}

class SymptomEntry {
  final String symptom;
  final double severity;
  final DateTime timestamp;
  final File? image;

  SymptomEntry({
    required this.symptom,
    required this.severity,
    required this.timestamp,
    this.image,
  });
}