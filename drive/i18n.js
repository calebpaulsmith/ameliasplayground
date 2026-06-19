// Bilingual strings for Amelia el Autobús.
// Every player-facing line lives here so the whole game flips ES <-> EN at once.

export const STR = {
  // Start screen
  title:        { es: 'Amelia el Autobús', en: 'Amelia the Bus' },
  subtitle:     { es: '¡Un autobús azul que habla y aprende!', en: 'A talking blue bus who loves to learn!' },
  story:        { es: 'Aventura', en: 'Story Adventure' },
  storySub:     { es: 'Sigue el GPS y completa misiones', en: 'Follow the GPS and complete missions' },
  explore:      { es: 'Explorar', en: 'Free Drive' },
  exploreSub:   { es: 'Maneja libre por la ciudad', en: 'Cruise around the city' },
  back:         { es: 'Atrás', en: 'Back' },
  howto:        { es: '¿Cómo se juega?', en: 'How to play' },
  howtoBody:    { es: 'Usa el volante para girar a la izquierda y a la derecha. Pisa VAMOS para avanzar y ALTO para frenar. En el semáforo: rojo = alto, verde = vamos. ¡Sigue la flecha del GPS!',
                  en: 'Use the wheel to steer left and right. Press GO to drive and STOP to brake. At the traffic light: red = stop, green = go. Follow the GPS arrow!' },

  // HUD / controls
  go:           { es: 'VAMOS', en: 'GO' },
  stop:         { es: 'ALTO', en: 'STOP' },
  left:         { es: 'Izquierda', en: 'Left' },
  right:        { es: 'Derecha', en: 'Right' },
  horn:         { es: 'Bocina', en: 'Horn' },
  resume:       { es: 'Seguir', en: 'Resume' },
  quit:         { es: 'Salir', en: 'Quit' },
  paused:       { es: 'En pausa', en: 'Paused' },

  // GPS directions
  goStraight:   { es: 'Sigue derecho', en: 'Go straight' },
  turnLeft:     { es: '¡Gira a la izquierda!', en: 'Turn left!' },
  turnRight:    { es: '¡Gira a la derecha!', en: 'Turn right!' },
  uTurn:        { es: 'Da la vuelta', en: 'Turn around' },
  arriving:     { es: '¡Ya casi llegamos!', en: 'Almost there!' },
  arrived:      { es: '¡Llegamos!', en: "We're here!" },

  // Traffic light
  redStop:      { es: 'Rojo. ¡Alto! Espera aquí.', en: 'Red light. Stop! Wait here.' },
  greenGo:      { es: '¡Verde! Ya podemos ir.', en: 'Green light! Now we can go.' },
  yellowSlow:   { es: 'Amarillo. Despacio…', en: 'Yellow. Slow down…' },
  goodStop:     { es: '¡Muy bien! Te paraste en rojo. 🌟', en: 'Great job stopping at the red light! 🌟' },
  ranRed:       { es: '¡Ups! En rojo nos paramos. Recuerda: rojo = alto.', en: 'Oops! We stop on red. Remember: red means stop.' },

  // Signs
  signStop:     { es: 'Señal de ALTO: para por completo.', en: 'STOP sign: come to a full stop.' },
  signSchool:   { es: 'Zona escolar: ve despacito.', en: 'School zone: drive slowly.' },
  signYield:    { es: 'Ceda el paso.', en: 'Yield to others.' },

  // Mission flow
  mDawn:        { es: '¡Buenos días, Amelia! Hora de trabajar. 🌅', en: 'Good morning, Amelia! Time to work. 🌅' },
  mGoStop:      { es: 'Vamos a recoger a un pasajero. Sigue la flecha hasta la parada.', en: "Let's pick up a passenger. Follow the arrow to the bus stop." },
  mPickup:      { es: 'Detente en la parada y abre las puertas.', en: 'Stop at the bus stop and open the doors.' },
  mBoarded:     { es: '¡{name} subió al autobús! 🎉', en: '{name} climbed aboard! 🎉' },
  mDropoff:     { es: 'Lleva a {name} al {place}. ¡Cuidado con los semáforos!', en: 'Take {name} to the {place}. Mind the traffic lights!' },
  mDelivered:   { es: '¡{name} llegó al {place}! Gracias, Amelia. 💛', en: '{name} made it to the {place}! Thank you, Amelia. 💛' },
  mHome:        { es: 'Buen trabajo. Regresa al taller con mamá mecánica. 🔧', en: 'Great work. Head back to the workshop with Mechanic Mom. 🔧' },
  mComplete:    { es: '¡Misión cumplida! 🏆 Mamá te da un abrazo.', en: 'Mission complete! 🏆 Mom gives you a big hug.' },
  allDone:      { es: '¡Terminaste todas las aventuras de hoy! Puedes explorar la ciudad. 🌟',
                  en: "You finished all of today's adventures! Now you can explore the city. 🌟" },

  // Passengers & places
  park:         { es: 'parque', en: 'park' },
  school:       { es: 'escuela', en: 'school' },
  market:       { es: 'mercado', en: 'market' },
  beach:        { es: 'playa', en: 'beach' },
  garage:       { es: 'taller', en: 'workshop' },

  // Mechanic mom & misc voice
  momHi:        { es: 'Hola mi autobusito. ¿Listo para rodar?', en: 'Hello my little bus. Ready to roll?' },
  fuelLow:      { es: '', en: '' },
  exploreHi:    { es: '¡A explorar la ciudad! Maneja con cuidado. 🚌', en: "Let's explore the city! Drive carefully. 🚌" },
  thanks:       { es: '¡Gracias por el viaje!', en: 'Thanks for the ride!' },
  bump:         { es: '¡Uy! Despacio.', en: 'Whoops! Slow down.' },
  honk:         { es: '¡Bip bip!', en: 'Beep beep!' },
};

export function t(id, lang, vars) {
  let s = (STR[id] && STR[id][lang]) || (STR[id] && STR[id].en) || id;
  if (vars) for (const k in vars) s = s.replace(new RegExp('\\{' + k + '\\}', 'g'), vars[k]);
  return s;
}
