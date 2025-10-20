// lib/screens/auth/login_screen.dart
// 20/10/2025 02:45
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/home/home_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _stayConnected = false;

  // MODIFICATION : Ajout d'un état de chargement local
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    setState(() {
      _stayConnected = settings.stayConnected;
    });

    if (settings.stayConnected) {
      _loginController.text = settings.savedLogin;
      _passwordController.text = await settings.getSavedPassword();
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      // 1. On active l'indicateur de chargement local
      setState(() { _isConnecting = true; });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

      try {
        final success = await authProvider.login(
          _loginController.text,
          _passwordController.text,
        );

        if (mounted && success) {
          await settingsProvider.saveCredentials(
            _loginController.text,
            _passwordController.text,
            _stayConnected,
          );

          final saleProvider = Provider.of<SaleProvider>(context, listen: false);
          final blProvider = Provider.of<BlControlProvider>(context, listen: false);
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

          // 2. Le spinner local reste visible pendant ce temps
          await Future.wait([
            authProvider.loadOfficineInfo(),
            saleProvider.fetchPreventes(),
            blProvider.fetchBonsLivraison(dtStart: today, dtEnd: today, query: ''),
            saleProvider.fetchPaymentMethodsWithQr(),
          ]);

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Constants.showSnackBar(context, "Erreur de connexion: $e", isError: true);
        }
      } finally {
        // 3. On désactive l'indicateur de chargement si on est toujours sur la page
        if (mounted) {
          setState(() { _isConnecting = false; });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connexion'),
            actions: [
              Row(
                children: [
                  const Text('Local', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: settings.isRemote,
                    onChanged: (value) {
                      if (value && settings.remoteIp.isEmpty) {
                        Constants.showSnackBar(
                          context,
                          'Veuillez renseigner une IP Distante dans la configuration.',
                          isError: true,
                        );
                        return;
                      }
                      settings.setConnectionMode(value);
                    },
                  ),
                  const Text('Distant', style: TextStyle(fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen()));
                    },
                    tooltip: 'Configuration',
                  ),
                ],
              ),
            ],
          ),
          body: child,
        );
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_open, size: 60, color: AppColors.primary),
                  const SizedBox(height: 20),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _loginController,
                    decoration: const InputDecoration(labelText: 'Login', prefixIcon: Icon(Icons.person)),
                    validator: (value) => value!.isEmpty ? 'Veuillez saisir votre login' : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                    validator: (value) => value!.isEmpty ? 'Veuillez saisir votre mot de passe' : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _stayConnected,
                          onChanged: (value) {
                            setState(() {
                              _stayConnected = value ?? false;
                            });
                          },
                        ),
                        const Text('Rester connecté'),
                      ],
                    ),
                  ),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.status == AuthStatus.Unauthenticated && auth.errorMessage != null) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: Text(
                            auth.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      // MODIFICATION : Le bouton vérifie l'état local OU l'état du provider
                      return (auth.status == AuthStatus.Loading || _isConnecting)
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                        child: const Text('Se connecter'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}