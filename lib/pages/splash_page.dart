part of '../main.dart';

class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key});

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppDecor.heroGradient(colorScheme),
            ),
          ),
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.onPrimary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.onPrimary.withValues(alpha: 0.1),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 98,
                      height: 98,
                      decoration: BoxDecoration(
                        color: colorScheme.onPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colorScheme.onPrimary.withValues(alpha: 0.32),
                        ),
                        boxShadow: AppDecor.softShadow(colorScheme),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/app_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Microfast Ltd',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '(Invoices Scanner)',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color:
                                colorScheme.onPrimary.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: 240,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const ProjectListPage()),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.onPrimary,
                          foregroundColor: colorScheme.primary,
                        ),
                        child: const Text('Start'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 240,
                      child: OutlinedButton(
                        onPressed: () => SystemNavigator.pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.onPrimary,
                          side: BorderSide(
                            color: colorScheme.onPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

