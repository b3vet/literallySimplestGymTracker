class Tip {
  const Tip({required this.title, required this.body});
  final String title;
  final String body;
}

const List<Tip> tips = [
  Tip(
    title: 'RIR is your honest effort',
    body:
        'RIR (reps in reserve) means how many more reps you could have done with good form. 0 = total failure, 2–3 = a few reps left in the tank. Be honest; it improves progression tracking.',
  ),
  Tip(
    title: 'Progressive overload > heavy random',
    body:
        'The most reliable strength driver is adding a rep or a small amount of weight most weeks on your main lifts. Stats screen will show you this trend.',
  ),
  Tip(
    title: 'Log the reps you actually did',
    body:
        'Even if you fall short of the target range, log what happened. Clean data is more useful than vanity data.',
  ),
  Tip(
    title: 'Rest long enough on compounds',
    body:
        'For squats, deadlifts, presses, 2–3 minutes rest between sets is usually optimal for strength. Isolation work can rest less.',
  ),
  Tip(
    title: 'Track every set',
    body:
        'It is tempting to skip "warmup" sets. Track working sets. The habit matters more than any one session.',
  ),
];
