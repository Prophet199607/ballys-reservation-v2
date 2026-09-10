import 'package:ballys_reservation_app/data/repositories/airport_repository.dart';
import 'package:ballys_reservation_app/data/repositories/gifts_repository.dart';
import 'package:ballys_reservation_app/data/repositories/guest_booking_repository.dart';
import 'package:ballys_reservation_app/data/repositories/inactive_members_repository.dart';
import 'package:ballys_reservation_app/data/repositories/member_profile_repository.dart';
import 'package:ballys_reservation_app/data/services/api_service.dart';
import 'package:ballys_reservation_app/main.dart';
import 'package:ballys_reservation_app/models/Guest/guest_booking.dart';
import 'package:ballys_reservation_app/models/birthday.dart';
import 'package:ballys_reservation_app/screens/Inactive_memberMain.dart';
import 'package:ballys_reservation_app/screens/academic_screen.dart';
import 'package:ballys_reservation_app/screens/member_visits/cdd_cards_screen.dart';
import 'package:ballys_reservation_app/models/cdd/cdd_history_item.dart';
import 'package:ballys_reservation_app/screens/member_visits/cdd_names_screen.dart';
import 'package:ballys_reservation_app/models/gift/birthday_gift_request.dart';
import 'package:ballys_reservation_app/models/gift/special_gift_request.dart';
import 'package:ballys_reservation_app/models/guest_modal.dart';
import 'package:ballys_reservation_app/models/guest_reservation_entryBallys.dart';
import 'package:ballys_reservation_app/screens/air_ticket_screen.dart';
import 'package:ballys_reservation_app/screens/approve_reject_show_screen.dart';
import 'package:ballys_reservation_app/screens/auth/login_screen.dart';
import 'package:ballys_reservation_app/screens/auth/otpVerification_screen.dart';
import 'package:ballys_reservation_app/screens/birthdayGiftRequestScreen.dart';
import 'package:ballys_reservation_app/screens/birthday_gift_price_increase_screen.dart';
import 'package:ballys_reservation_app/screens/birthday_screen.dart';
import 'package:ballys_reservation_app/screens/daily_walking_guests/daily_walking_guests%20_screen.dart';
import 'package:ballys_reservation_app/screens/chat_screen.dart';
import 'package:ballys_reservation_app/models/follow_up_item.dart';
import 'package:ballys_reservation_app/screens/follow_up_view_screen.dart';
import 'package:ballys_reservation_app/screens/follow_ups_screen.dart';
import 'package:ballys_reservation_app/screens/gifts/gifts_main.dart';
import 'package:ballys_reservation_app/screens/gifts/guest_gifts_screen.dart';
import 'package:ballys_reservation_app/screens/gifts/gifts_screen.dart';
import 'package:ballys_reservation_app/screens/gifts/new_gift_request.dart';
import 'package:ballys_reservation_app/screens/gifts/previous_gift.dart';
import 'package:ballys_reservation_app/screens/gifts/special_gift_request_screen.dart';
import 'package:ballys_reservation_app/screens/gifts/view_special_gift.dart';
import 'package:ballys_reservation_app/screens/guest_booking_screen.dart';
import 'package:ballys_reservation_app/screens/home_screen.dart';
import 'package:ballys_reservation_app/screens/inactive_members.dart';
import 'package:ballys_reservation_app/screens/member_visits.dart';
import 'package:ballys_reservation_app/screens/notifications_screen.dart';
import 'package:ballys_reservation_app/screens/member_visits/cdd_view_screen.dart';
import 'package:ballys_reservation_app/screens/member_visits/customer_due_diligence_screen.dart';
import 'package:ballys_reservation_app/screens/member_visits/sales_persons.dart';
import 'package:ballys_reservation_app/screens/membersMainScreen.dart';
import 'package:ballys_reservation_app/screens/members_screen.dart';
import 'package:ballys_reservation_app/screens/profile/guest_performance/guest_performance_screen.dart';
import 'package:ballys_reservation_app/screens/profile/member_summary_screen.dart';
import 'package:ballys_reservation_app/screens/profile/profile_screen.dart';
import 'package:ballys_reservation_app/screens/menu_screen.dart';
import 'package:ballys_reservation_app/screens/profile/trip_history_screen.dart';
import 'package:ballys_reservation_app/screens/report_screen.dart';
import 'package:ballys_reservation_app/models/amendment_ballys.dart';
import 'package:ballys_reservation_app/screens/reservations/amendment_view_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/amendments_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/air_tickets_selection_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/air_tickets_selection_screen.dart';
import 'package:ballys_reservation_app/models/coordinator_request.dart';
import 'package:ballys_reservation_app/screens/reservations/coordinator_request_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/coordinator_requests_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/group_reservation_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/main_reservation.dart';
import 'package:ballys_reservation_app/screens/reservations/air_ticket_amendment_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/hotel_amendment_ballys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/new_reservationBallys_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/new_reservation_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/quick_reservation_ballys.dart';
import 'package:ballys_reservation_app/screens/reservations/quick_reservation_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/reservation_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/reservation_screen_ballys.dart';
import 'package:ballys_reservation_app/screens/reservations/reservation_view_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/reservation_view_screen_ballys.dart';
import 'package:ballys_reservation_app/screens/reservations/transport_add_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/transport_screen.dart';
import 'package:ballys_reservation_app/screens/reservations/transport_view_screen.dart';
import 'package:ballys_reservation_app/screens/settings_screen.dart';
import 'package:ballys_reservation_app/screens/support_screen.dart';
import 'package:ballys_reservation_app/screens/viewBirthdayGiftRequest.dart';
import 'package:ballys_reservation_app/screens/view_guest_booking.dart';
import 'package:ballys_reservation_app/wrappers/main_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ballys_reservation_app/main.dart' show navigatorKey;
import 'package:ballys_reservation_app/utils/secure_storage.dart';

class AppNavigation {
  AppNavigation._();

  static String initialRoute = '/splash';

  /// Location of the transport list, optionally asking it to reveal and
  /// highlight one request — used by every transport notification tap.
  static String transportLocation([String? masterId]) {
    final id = masterId?.trim() ?? '';
    return id.isEmpty
        ? '/reservationMain/transport'
        : '/reservationMain/transport?masterId=${Uri.encodeComponent(id)}';
  }

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialRoute,
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            child: const LoginScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          );
        },
      ),
      GoRoute(
        path: '/otp-verification',
        pageBuilder: (context, state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            child: OTPVerificationScreen(
              phoneNumber: extra['phoneNumber'] as String,
              username: extra['username'] as String,
              password: extra['password'] as String,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(1.0, 0.0),
                          end: Offset.zero,
                        ).animate(
                          CurveTween(
                            curve: Curves.easeInOut,
                          ).animate(animation),
                        ),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => MainWrapper(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const HomeScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'profile',
                pageBuilder: (context, state) {
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: const ProfileScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
                routes: [
                  GoRoute(
                    path: 'guest-performance',
                    pageBuilder: (context, state) {
                      return CustomTransitionPage(
                        fullscreenDialog: false,
                        key: state.pageKey,
                        child: GuestPerformanceScreen(
                          memberProfileRepository: MemberProfileRepository(
                            ApiService(SecureStorage.instance),
                          ),
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: CurveTween(
                                  curve: Curves.easeInOutCirc,
                                ).animate(animation),
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                  GoRoute(
                    path: 'member-summary',
                    pageBuilder: (context, state) {
                      return CustomTransitionPage(
                        fullscreenDialog: false,
                        key: state.pageKey,
                        child: MemberSummaryScreen(
                          memberProfileRepository: MemberProfileRepository(
                            ApiService(SecureStorage.instance),
                          ),
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: CurveTween(
                                  curve: Curves.easeInOutCirc,
                                ).animate(animation),
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                  GoRoute(
                    path: 'trip-history',
                    pageBuilder: (context, state) {
                      return CustomTransitionPage(
                        fullscreenDialog: false,
                        key: state.pageKey,
                        child: TripHistoryScreen(
                          memberProfileRepository: MemberProfileRepository(
                            ApiService(SecureStorage.instance),
                          ),
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: CurveTween(
                                  curve: Curves.easeInOutCirc,
                                ).animate(animation),
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'notifications',
                pageBuilder: (context, state) {
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: const NotificationsScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
                routes: const [],
              ),
              GoRoute(
                path: 'member-visits',
                pageBuilder: (context, state) {
                  final Map<String, dynamic> data =
                      state.extra as Map<String, dynamic>;
                  final String title = data['title'] as String;
                  final List<Guest> guestList =
                      data['guestList'] as List<Guest>;
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: MemberVisits(title: title, guestList: guestList),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
                routes: const [],
              ),
              GoRoute(
                path: 'sales-persons',
                pageBuilder: (context, state) {
                  final Map<String, dynamic> data =
                      state.extra as Map<String, dynamic>;
                  final String title = data['title'] as String;
                  final Map<String, List<Guest>> salesPersons =
                      data['salesPersons'] as Map<String, List<Guest>>;
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: SalesPersonsScreen(
                      title: title,
                      salesPersons: salesPersons,
                    ),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
                routes: const [],
              ),
            ],
          ),
          // GoRoute(
          //   path: '/reservations',
          //   pageBuilder: (context, state) => CustomTransitionPage(
          //     fullscreenDialog: true,
          //     key: state.pageKey,
          //     child: const ReservationScreen(),
          //     transitionsBuilder:
          //         (context, animation, secondaryAnimation, child) {
          //           return FadeTransition(
          //             opacity: CurveTween(
          //               curve: Curves.easeInOutCirc,
          //             ).animate(animation),
          //             child: child,
          //           );
          //         },
          //   ),
          //   routes: [
          //     GoRoute(
          //       path: 'new-reservation',
          //       pageBuilder: (context, state) {
          //         return CustomTransitionPage(
          //           fullscreenDialog: false,
          //           key: state.pageKey,
          //           child: const NewReservationScreen(),
          //           transitionsBuilder:
          //               (context, animation, secondaryAnimation, child) {
          //                 return FadeTransition(
          //                   opacity: CurveTween(
          //                     curve: Curves.easeInOutCirc,
          //                   ).animate(animation),
          //                   child: child,
          //                 );
          //               },
          //         );
          //       },
          //       routes: [
          //         GoRoute(
          //           path: 'air-tickets-selection',
          //           pageBuilder: (context, state) {
          //             final Map<String, dynamic> data =
          //                 state.extra as Map<String, dynamic>;
          //             final arrivalDate = data['arrivalDate'] ?? '';
          //             final departureDate = data['departureDate'] ?? '';
          //             return CustomTransitionPage(
          //               fullscreenDialog: false,
          //               key: state.pageKey,
          //               child: AirTicketsSelectionScreen(
          //                 AirportRepository(
          //                   ApiService(SecureStorage.instance),
          //                 ),
          //                 arrivalDate: arrivalDate,
          //                 departureDate: departureDate,
          //               ),
          //               transitionsBuilder:
          //                   (context, animation, secondaryAnimation, child) {
          //                     return FadeTransition(
          //                       opacity: CurveTween(
          //                         curve: Curves.easeInOutCirc,
          //                       ).animate(animation),
          //                       child: child,
          //                     );
          //                   },
          //             );
          //           },
          //         ),
          //       ],
          //     ),
          //     GoRoute(
          //       path: 'reservation-view',
          //       pageBuilder: (context, state) {
          //         return CustomTransitionPage(
          //           fullscreenDialog: false,
          //           key: state.pageKey,
          //           child: const ReservationViewScreen(),
          //           transitionsBuilder:
          //               (context, animation, secondaryAnimation, child) {
          //                 return FadeTransition(
          //                   opacity: CurveTween(
          //                     curve: Curves.easeInOutCirc,
          //                   ).animate(animation),
          //                   child: child,
          //                 );
          //               },
          //         );
          //       },
          //     ),
          //   ],
          // ),
          GoRoute(
  path: '/reservationMain',
  pageBuilder: (context, state) => CustomTransitionPage(
    fullscreenDialog: true,
    key: state.pageKey,
    child: const ReservationMainScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
        child: child,
      );
    },
  ),
  routes: [
    // Existing reservation screen (reused)
    GoRoute(
      path: 'reservations',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const ReservationScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
      routes: [
        GoRoute(
          path: 'new-reservation',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const NewReservationScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
          routes: [
            GoRoute(
              path: 'air-tickets-selection',
              pageBuilder: (context, state) {
                final Map<String, dynamic> data =
                    state.extra as Map<String, dynamic>;
                final arrivalDate = data['arrivalDate'] ?? '';
                final departureDate = data['departureDate'] ?? '';
                return CustomTransitionPage(
                  fullscreenDialog: false,
                  key: state.pageKey,
                  child: AirTicketsSelectionScreen(
                    AirportRepository(ApiService(SecureStorage.instance)),
                    arrivalDate: arrivalDate,
                    departureDate: departureDate,
                  ),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                      child: child,
                    );
                  },
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: 'new-reservation-ballys',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            // Opened from a card on "My Coordinator Requests" with the request
            // as `extra`: the coordinator keys in the reservation somebody
            // else asked for. Null on the normal "new reservation" path.
            child: NewReservationBallysScreen(
              coordinatorRequest: state.extra is CoordinatorRequestRecord
                  ? state.extra as CoordinatorRequestRecord
                  : null,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
          routes: [
            GoRoute(
              path: 'air-tickets-selection',
              pageBuilder: (context, state) {
                final Map<String, dynamic> data =
                    state.extra as Map<String, dynamic>;
                final arrivalDate = data['arrivalDate'] ?? '';
                final departureDate = data['departureDate'] ?? '';
                // Everyone on the reservation, so a ticket can be assigned to
                // the guest(s) it is booked for.
                final guests =
                    (data['guests'] as List<AccompanyingMember>?) ??
                        const <AccompanyingMember>[];
                return CustomTransitionPage(
                  fullscreenDialog: false,
                  key: state.pageKey,
                  child: AirTicketsSelectionBallysScreen(
                    AirportRepository(ApiService(SecureStorage.instance)),
                    arrivalDate: arrivalDate,
                    departureDate: departureDate,
                    guests: guests,
                  ),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                      child: child,
                    );
                  },
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: 'reservation-view',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const ReservationViewScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
        // Ballys detail view — reads the Ballys reservation selected by
        // ReservationScreenBallys.
        GoRoute(
          path: 'reservation-view-ballys',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const ReservationViewScreenBallys(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
        // Amendment screens — pushed from the Amendment button on the Ballys
        // detail view once the user picks hotel or air ticket. Both read the
        // selection providers that view already populated.
        GoRoute(
          path: 'hotel-amendment-ballys',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const HotelAmendmentBallysScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: 'air-ticket-amendment-ballys',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const AirTicketAmendmentBallysScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
      ],
    ),

    // Reservations list — Ballys logins get their own screen, which pushes the
    // Ballys new-reservation / view screens under 'reservations' above.
    GoRoute(
      path: 'reservations-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const ReservationScreenBallys(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // Amendments (Ballys only) — everything raised from the hotel / air ticket
    // amendment screens, in the same four-tab check → approve workflow the
    // reservation list uses. The detail screen takes the row itself as `extra`,
    // since the list has already parsed and joined it.
    GoRoute(
      path: 'amendments-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const AmendmentsBallysScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
      routes: [
        GoRoute(
          path: 'amendment-view-ballys',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: AmendmentViewBallysScreen(
              amendment: state.extra as AmendmentBallys,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
      ],
    ),

    // Quick Reservation — shared screen for every non-Ballys location
    GoRoute(
      path: 'quick-reservation',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const QuickReservationScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // Quick Reservation — Ballys logins get their own screen
    GoRoute(
      path: 'quick-reservation-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const QuickReservationBallysScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // Group reservation (Ballys only) — a party arriving together, keyed in as
    // one lead guest plus an uploaded sheet of everybody else.
    GoRoute(
      path: 'group-reservation-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const GroupReservationBallysScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // Coordinator Request (Ballys only) — an executive hands the reservation
    // to a coordinator instead of keying it in themselves.
    GoRoute(
      path: 'coordinator-request-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const CoordinatorRequestBallysScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // The read side of the above — every coordinator request the logged-in
    // user has sent.
    GoRoute(
      path: 'coordinator-requests-ballys',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: const CoordinatorRequestsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
    ),

    // Transport (Bellagio only)
    // `?masterId=` comes from a transport push notification and tells the
    // screen which request to reveal.
    GoRoute(
      path: 'transport',
      pageBuilder: (context, state) => CustomTransitionPage(
        fullscreenDialog: false,
        key: state.pageKey,
        child: TransportScreen(
          highlightMasterId: state.uri.queryParameters['masterId'],
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          );
        },
      ),
      routes: [
        GoRoute(
          path: 'transport-view',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const TransportViewScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
        GoRoute(
          path: 'transport-add',
          pageBuilder: (context, state) => CustomTransitionPage(
            fullscreenDialog: false,
            key: state.pageKey,
            child: const TransportAddScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
                child: child,
              );
            },
          ),
        ),
      ],
    ),

  ],
),
          GoRoute(
            path: '/support',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const SupportScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const SettingsScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
          ),
          GoRoute(
  path: '/academic',
  pageBuilder: (context, state) => CustomTransitionPage(
    fullscreenDialog: true,
    key: state.pageKey,
    child: const AcademicScreen(),
    transitionsBuilder:
        (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurveTween(
              curve: Curves.easeInOutCirc,
            ).animate(animation),
            child: child,
          );
        },
  ),
),
          GoRoute(
            path: '/birthdays',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: BirthdayScreen(
                giftsRepository: GiftsRepository(
                  ApiService(SecureStorage.instance),
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'gift-price-increase',
                pageBuilder: (context, state) {
                  final birthday = state.extra as Birthday;
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: BirthdayGiftPriceIncreaseScreen(
                      birthday: birthday,
                      giftsRepository: GiftsRepository(
                        ApiService(SecureStorage.instance),
                      ),
                    ),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
              ),
            ],
          ),

           GoRoute(
  path: '/inctiveMemberMain',
  pageBuilder: (context, state) => CustomTransitionPage(
    fullscreenDialog: true,
    key: state.pageKey,
    child: const InactiveMembermainScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
        child: child,
      );
    },
  ),
  routes: [
          GoRoute(
            path: '/inactive-members',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: InactiveMembersScreen(
                inactiveMembersRepository: InactiveMembersRepository(
                  ApiService(SecureStorage.instance),
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
          ),
          GoRoute(
            path: '/followups',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const FollowUpsScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'view',
                pageBuilder: (context, state) {
                  final item = state.extra as FollowUpItem;
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: FollowUpViewScreen(item: item),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
              ),
            ],
          ),

        ]),
          GoRoute(
            path: '/gifts',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: false,
              key: state.pageKey,
              child: GiftsMainScreen(
                giftsRepository: GiftsRepository(
                  ApiService(SecureStorage.instance),
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'event-gifts',
                pageBuilder: (context, state) => CustomTransitionPage(
                  fullscreenDialog: false,
                  key: state.pageKey,
                  child: GiftsScreen(
                    giftsRepository: GiftsRepository(
                      ApiService(SecureStorage.instance),
                    ),
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: CurveTween(
                            curve: Curves.easeInOutCirc,
                          ).animate(animation),
                          child: child,
                        );
                      },
                ),
                routes: [
                  GoRoute(
                    path: 'guest-gifts/:mid',
                    pageBuilder: (context, state) {
                      final String mid = state.pathParameters['mid']!;
                      return CustomTransitionPage(
                        fullscreenDialog: false,
                        key: state.pageKey,
                        child: GuestGiftsScreen(
                          giftsRepository: GiftsRepository(
                            ApiService(SecureStorage.instance),
                          ),
                          mid: mid,
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: CurveTween(
                                  curve: Curves.easeInOutCirc,
                                ).animate(animation),
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: '/special-gift-requests',
                pageBuilder: (context, state) => CustomTransitionPage(
                  fullscreenDialog: false,
                  key: state.pageKey,
                  child: SpecialGiftRequestScreen(
                    giftsRepository: GiftsRepository(
                      ApiService(SecureStorage.instance),
                    ),
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: CurveTween(
                            curve: Curves.easeInOutCirc,
                          ).animate(animation),
                          child: child,
                        );
                      },
                ),
                routes: [
                  GoRoute(
                    path: 'new-gift-request',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      fullscreenDialog: false,
                      key: state.pageKey,
                      child: NewGiftRequest(
                        giftsRepository: GiftsRepository(
                          ApiService(SecureStorage.instance),
                        ),
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: CurveTween(
                                curve: Curves.easeInOutCirc,
                              ).animate(animation),
                              child: child,
                            );
                          },
                    ),
                  ),
                  GoRoute(
                    path: 'prv-gifts/:mid',
                    pageBuilder: (context, state) {
                      final String mid = state.pathParameters['mid']!;
                      final extra = state.extra as Map<String, dynamic>? ?? {};
                      final int iid = extra['iid'] as int? ?? 8888;
                      final text2 = extra['text2'] as String? ?? "";
                      return CustomTransitionPage(
                        fullscreenDialog: false,
                        key: state.pageKey,
                        child: PrvGiftScreen(
                          memberId: mid,
                          giftsRepository: GiftsRepository(
                            ApiService(SecureStorage.instance),
                          ),
                          iid: iid,
                           text2: text2,
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeInOutCirc,
                                ),
                                child: child,
                              );
                            },
                      );
                    },
                  ),
                GoRoute(
  path: 'view-specific-gift-request',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    final gift = extra['gift'] as SpecialGiftRequest?;
    final isPending = extra['isPending'] as bool? ?? false;
    final isApproved = extra['isApproved'] as bool? ?? false;
    final isChecked = extra['isChecked'] as bool? ?? false;
    final isIssued = extra['isIssued'] as bool? ?? false;  // ← ADD THIS
    final isViewOnly = extra['isViewOnly'] as bool? ?? false;
    return ViewSpecificGiftRequest(
      giftsRepository: GiftsRepository(
        ApiService(SecureStorage.instance),
      ),
      gift: gift,
      isPending: isPending,
      isApproved: isApproved,
      isChecked: isChecked,
      isIssued: isIssued,  // ← ADD THIS
      isViewOnly: isViewOnly,
    );
  },
),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/memberMain',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: MemberMainScreen(
                // giftsRepository: GiftsRepository(
                //   ApiService(SecureStorage.instance),
                // ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: '/members',
                pageBuilder: (context, state) => CustomTransitionPage(
                  fullscreenDialog: true,
                  key: state.pageKey,
                  child: MembersScreen(
                    giftsRepository: GiftsRepository(
                      ApiService(SecureStorage.instance),
                    ),
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: CurveTween(
                            curve: Curves.easeInOutCirc,
                          ).animate(animation),
                          child: child,
                        );
                      },
                ),
              ),
              GoRoute(
                path: '/new_guest',
                pageBuilder: (context, state) => CustomTransitionPage(
                  fullscreenDialog: true,
                  key: state.pageKey,
                  child: CustomerDueDiligenceScreen(
                    // giftsRepository: GiftsRepository(
                    //   ApiService(SecureStorage.instance),
                    // ),
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: CurveTween(
                            curve: Curves.easeInOutCirc,
                          ).animate(animation),
                          child: child,
                        );
                      },
                ),
              ),
              // Inside the routes: [ ... ] of GoRoute(path: '/memberMain', ...)

// Inside routes: [ ... ] of GoRoute(path: '/memberMain', ...)
// REPLACE the old /cdd-history routes with these:

GoRoute(
  path: '/cdd',
  redirect: (_, __) => '/memberMain/cdd/names',
),

GoRoute(
  path: '/cdd/names',
  pageBuilder: (context, state) => CustomTransitionPage(
    fullscreenDialog: true,
    key: state.pageKey,
    child: const CddNamesScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
          child: child,
        ),
  ),
),

GoRoute(
  path: '/cdd/cards',
  pageBuilder: (context, state) {
    final items = state.extra as List<CddHistoryItem>;
    return CustomTransitionPage(
      key: state.pageKey,
      child: CddCardsScreen(items: items),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          ),
    );
  },
),

GoRoute(
  path: '/cdd/view',
  pageBuilder: (context, state) {
    final item = state.extra as CddHistoryItem;
    return CustomTransitionPage(
      key: state.pageKey,
      child: CddViewScreen(item: item),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
            child: child,
          ),
    );
  },
),

GoRoute(
  path: '/cdd/new',
  pageBuilder: (context, state) => CustomTransitionPage(
    fullscreenDialog: true,
    key: state.pageKey,
    child: const CustomerDueDiligenceScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOutCirc).animate(animation),
          child: child,
        ),
  ),
),
            ],
          ),
          GoRoute(
            path: '/daily-gests',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const DailyWalkingGuestScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
          ),
          GoRoute(
            path: '/aireticketscreen',
            builder: (context, state) => const AirTicketScreen(),
          ),
          GoRoute(
            path: '/guest-bookings',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: GuestBookingScreen(
                bookingRepository: GuestBookingRepository(
                  ApiService(SecureStorage.instance),
                  SecureStorage.instance,
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'view-booking',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  final booking = extra['booking'] as GuestBooking?;
                  final isPending = extra['isPending'] as bool? ?? false;
                  return ViewGuestBooking(
                    bookingRepository: GuestBookingRepository(
                      ApiService(SecureStorage.instance),
                      SecureStorage.instance,
                    ),
                    booking: booking,
                    isPending: isPending,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/menu',
            pageBuilder: (context, state) => CustomTransitionPage(
              fullscreenDialog: true,
              key: state.pageKey,
              child: const MenuScreen(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurveTween(
                        curve: Curves.easeInOutCirc,
                      ).animate(animation),
                      child: child,
                    );
                  },
            ),
            routes: [
              GoRoute(
                path: 'chats',
                pageBuilder: (context, state) {
                  final notificationData = state.extra as Map<String, dynamic>?;
                  return CustomTransitionPage(
                    fullscreenDialog: false,
                    key: state.pageKey,
                    child: ChatScreen(notificationData: notificationData),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: CurveTween(
                              curve: Curves.easeInOutCirc,
                            ).animate(animation),
                            child: child,
                          );
                        },
                  );
                },
              ),
              GoRoute(
                path: 'approve-reject',
                builder: (context, state) => const ApproveScreen(),
                routes: [
                  GoRoute(
                    path: '/reservations',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      fullscreenDialog: true,
                      key: state.pageKey,
                      child: const ReservationScreen(hideAddButton: true),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: CurveTween(
                                curve: Curves.easeInOutCirc,
                              ).animate(animation),
                              child: child,
                            );
                          },
                    ),
                    routes: [
                      GoRoute(
                        path: 'new-reservation',
                        pageBuilder: (context, state) {
                          return CustomTransitionPage(
                            fullscreenDialog: false,
                            key: state.pageKey,
                            child: const NewReservationScreen(),
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  return FadeTransition(
                                    opacity: CurveTween(
                                      curve: Curves.easeInOutCirc,
                                    ).animate(animation),
                                    child: child,
                                  );
                                },
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'air-tickets-selection',
                            pageBuilder: (context, state) {
                              final Map<String, dynamic> data =
                                  state.extra as Map<String, dynamic>;
                              final arrivalDate = data['arrivalDate'] ?? '';
                              final departureDate = data['departureDate'] ?? '';
                              return CustomTransitionPage(
                                fullscreenDialog: false,
                                key: state.pageKey,
                                child: AirTicketsSelectionScreen(
                                  AirportRepository(
                                    ApiService(SecureStorage.instance),
                                  ),
                                  arrivalDate: arrivalDate,
                                  departureDate: departureDate,
                                ),
                                transitionsBuilder:
                                    (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) {
                                      return FadeTransition(
                                        opacity: CurveTween(
                                          curve: Curves.easeInOutCirc,
                                        ).animate(animation),
                                        child: child,
                                      );
                                    },
                              );
                            },
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'reservation-view',
                        pageBuilder: (context, state) {
                          return CustomTransitionPage(
                            fullscreenDialog: false,
                            key: state.pageKey,
                            child: const ReservationViewScreen(),
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  return FadeTransition(
                                    opacity: CurveTween(
                                      curve: Curves.easeInOutCirc,
                                    ).animate(animation),
                                    child: child,
                                  );
                                },
                          );
                        },
                      ),
                    ],
                  ),
                  // Approve → Reservations for Ballys logins. Same list the
                  // Ballys Reservations menu shows, minus the add button —
                  // nothing is created from the Approve flow.
                  GoRoute(
                    path: '/reservations-ballys',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      fullscreenDialog: true,
                      key: state.pageKey,
                      child: const ReservationScreenBallys(hideAddButton: true),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: CurveTween(
                                curve: Curves.easeInOutCirc,
                              ).animate(animation),
                              child: child,
                            );
                          },
                    ),
                  ),
                  GoRoute(
                    path: '/special-gift-requests',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      fullscreenDialog: false,
                      key: state.pageKey,
                      child: SpecialGiftRequestScreen(
                        giftsRepository: GiftsRepository(
                          ApiService(SecureStorage.instance),
                        ),
                        hideAddButton: true,
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: CurveTween(
                                curve: Curves.easeInOutCirc,
                              ).animate(animation),
                              child: child,
                            );
                          },
                    ),
                    routes: [
                      GoRoute(
                        path: 'new-gift-request',
                        pageBuilder: (context, state) => CustomTransitionPage(
                          fullscreenDialog: false,
                          key: state.pageKey,
                          child: NewGiftRequest(
                            giftsRepository: GiftsRepository(
                              ApiService(SecureStorage.instance),
                            ),
                          ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: CurveTween(
                                    curve: Curves.easeInOutCirc,
                                  ).animate(animation),
                                  child: child,
                                );
                              },
                        ),
                      ),
                      GoRoute(
                        path: 'prv-gifts/:mid',
                        pageBuilder: (context, state) {
                          final String mid = state.pathParameters['mid']!;
                          final extra =
                              state.extra as Map<String, dynamic>? ?? {};
                          final int iid = extra['iid'] as int? ?? 8888;
                          final text2 = extra['text2'] as String? ?? "";
                          return CustomTransitionPage(
                            fullscreenDialog: false,
                            key: state.pageKey,
                            child: PrvGiftScreen(
                              memberId: mid,

                              giftsRepository: GiftsRepository(
                                ApiService(SecureStorage.instance),
                              ),
                              iid: iid,
                               text2: text2,
                            ),
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  return FadeTransition(
                                    opacity: CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOutCirc,
                                    ),
                                    child: child,
                                  );
                                },
                          );
                        },
                      ),
                   GoRoute(
  path: 'view-specific-gift-request',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    final gift = extra['gift'] as SpecialGiftRequest?;
    final isPending = extra['isPending'] as bool? ?? false;
    final isApproved = extra['isApproved'] as bool? ?? false;
    final isChecked = extra['isChecked'] as bool? ?? false;
    final isIssued = extra['isIssued'] as bool? ?? false;  // ← ADD THIS
    final isViewOnly = extra['isViewOnly'] as bool? ?? false;
    return ViewSpecificGiftRequest(
      giftsRepository: GiftsRepository(
        ApiService(SecureStorage.instance),
      ),
      gift: gift,
      isPending: isPending,
      isApproved: isApproved,
      isChecked: isChecked,
      isIssued: isIssued,  // ← ADD THIS
      isViewOnly: isViewOnly,
    );
  },
),
                    ],
                  ),
                  GoRoute(
                    path: '/birthday-gifts',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      fullscreenDialog: true,
                      key: state.pageKey,
                      child: BirthdayGiftRequestScreen(
                        giftsRepository: GiftsRepository(
                          ApiService(SecureStorage.instance),
                        ),
                        hideAddButton: true,
                      ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: CurveTween(
                                curve: Curves.easeInOutCirc,
                              ).animate(animation),
                              child: child,
                            );
                          },
                    ),
                    routes: [
                      // ── View Birthday Gift Request ─────────────────────────────
                      // Now passes isChecked so the detail screen knows which tab
                      // opened it and renders the correct buttons.
                      GoRoute(
                        path: 'view-birthday-gift-request',
                        builder: (context, state) {
                          final extra =
                              state.extra as Map<String, dynamic>? ?? {};
                          final gift =
                              extra['gift'] as BirthdayIncressGiftRequest?;
                          final isPending =
                              extra['isPending'] as bool? ?? false;
                          final isApproved =
                              extra['isApproved'] as bool? ?? false;
                          final isChecked =
                              extra['isChecked'] as bool? ?? false; // ← fixed
                          final isIssued = extra['isIssued'] as bool? ?? false;
                            final isViewOnly = extra['isViewOnly'] as bool? ?? false; 
                          return ViewBirthdayGiftRequest(
                            giftsRepository: GiftsRepository(
                              ApiService(SecureStorage.instance),
                            ),
                            gift: gift,
                            isPending: isPending,
                            isApproved: isApproved,
                            isChecked: isChecked, // ← passed through
                            isIssued: isIssued, 
                            isViewOnly: isViewOnly,
                          );
                        },
                      ),
                      GoRoute(
                        path: 'prv-gifts/:mid',
                        pageBuilder: (context, state) {
                          final String mid = state.pathParameters['mid']!;
                          final extra =
                              state.extra as Map<String, dynamic>? ?? {};
                          final int iid = extra['iid'] as int? ?? 8888;
                           final text2 = extra['text2'] as String? ?? "";
                          return CustomTransitionPage(
                            fullscreenDialog: false,
                            key: state.pageKey,
                            child: PrvGiftScreen(
                              memberId: mid,
                              giftsRepository: GiftsRepository(
                                ApiService(SecureStorage.instance),
                              ),
                              iid: iid,
                               text2: text2,
                            ),
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  return FadeTransition(
                                    opacity: CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOutCirc,
                                    ),
                                    child: child,
                                  );
                                },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
