const canvas = document.getElementById('live2d-canvas');
const stage = document.getElementById('stage');
const statusElement = document.getElementById('status');

let app;
let model;
let targetMouthOpen = 0;
let currentMouthOpen = 0;
let mood = 'calm';
let expression = 'neutral';
let motion = 'idle';
let intensity = 0.25;
let duration = 1.4;
let speaking = false;
let profile = {
  supportsNamedExpressions: false,
  expressionMap: {},
  lipSyncParameters: ['ParamMouthOpenY', 'ParamA']
};
let phase = 'idle';
let phaseStartedAt = performance.now();
let lastIdleMotionAt = 0;
let lastNamedExpression = '';
window.__companionDebugState = { mood, expression, motion, intensity, duration, speaking, targetMouthOpen, currentMouthOpen, phase };

function modelURL() {
  const params = new URLSearchParams(window.location.search);
  return params.get('model') || '/Avatars/Mao/Mao.model3.json';
}

function modelName() {
  const params = new URLSearchParams(window.location.search);
  return params.get('name') || 'Live2D';
}

function notifyHost(payload) {
  window.webkit?.messageHandlers?.live2dStatus?.postMessage(payload);
}

function setStatus(text, className) {
  statusElement.textContent = text;
  stage.classList.remove('loaded', 'error');
  if (className) {
    stage.classList.add(className);
  }
}

function fitModel() {
  if (!model || !app) return;

  const width = app.renderer.width;
  const height = app.renderer.height;
  const bounds = model.getLocalBounds();
  const scale = Math.min(width / Math.max(bounds.width, 1), height / Math.max(bounds.height, 1)) * 0.92;

  model.pivot.set(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  model.scale.set(scale);
  model.x = width * 0.5;
  model.y = height * 0.53;
}

function setParameter(id, value) {
  try {
    model?.internalModel?.coreModel?.setParameterValueById?.(id, value);
  } catch (error) {
    console.warn(`Could not set Live2D parameter ${id}`, error);
  }
}

function clamp(value, lower, upper) {
  return Math.min(upper, Math.max(lower, value));
}

function expressionParameters(nextExpression, nextIntensity) {
  const amount = clamp(nextIntensity || 0, 0, 1);
  const parameters = {
    mouthForm: 0,
    eyeOpen: 1,
    browY: 0,
    browAngleLeft: 0,
    browAngleRight: 0
  };

  if (nextExpression === 'smile') {
    parameters.mouthForm = 0.7 * amount;
    parameters.eyeOpen = 1 - 0.25 * amount;
    parameters.browY = 0.3 * amount;
  } else if (nextExpression === 'curious') {
    parameters.mouthForm = 0.18 * amount;
    parameters.eyeOpen = 1;
    parameters.browY = 0.18 * amount;
    parameters.browAngleLeft = -0.25 * amount;
    parameters.browAngleRight = 0.25 * amount;
  } else if (nextExpression === 'angry' || nextExpression === 'pout') {
    parameters.mouthForm = -0.8 * amount;
    parameters.eyeOpen = 1 - 0.1 * amount;
    parameters.browY = -0.75 * amount;
    parameters.browAngleLeft = -0.8 * amount;
    parameters.browAngleRight = 0.8 * amount;
  } else if (nextExpression === 'sad') {
    parameters.mouthForm = -0.45 * amount;
    parameters.eyeOpen = 1 - 0.2 * amount;
    parameters.browY = -0.25 * amount;
    parameters.browAngleLeft = 0.45 * amount;
    parameters.browAngleRight = -0.45 * amount;
  } else if (nextExpression === 'surprised') {
    parameters.mouthForm = 0.2 * amount;
    parameters.eyeOpen = 1;
    parameters.browY = 0.55 * amount;
  } else if (nextExpression === 'blush') {
    parameters.mouthForm = 0.35 * amount;
    parameters.eyeOpen = 1 - 0.32 * amount;
    parameters.browY = 0.25 * amount;
  }

  return parameters;
}

function applyExpression(nextExpression) {
  const expressionName = profile.expressionMap?.[nextExpression] || profile.expressionMap?.neutral || '';

  try {
    if (profile.supportsNamedExpressions && expressionName && expressionName !== lastNamedExpression && model?.internalModel?.model?.expressions?.has(expressionName)) {
      model.expression(expressionName);
      lastNamedExpression = expressionName;
    }
  } catch (error) {
    console.warn('Could not set Live2D expression', error);
  }

  const parameters = expressionParameters(nextExpression, intensity);
  setParameter('ParamMouthForm', parameters.mouthForm);
  setParameter('ParamEyeLOpen', parameters.eyeOpen);
  setParameter('ParamEyeROpen', parameters.eyeOpen);
  setParameter('ParamBrowLY', parameters.browY);
  setParameter('ParamBrowRY', parameters.browY);
  setParameter('ParamBrowLAngle', parameters.browAngleLeft);
  setParameter('ParamBrowRAngle', parameters.browAngleRight);
}

function triggerIdleMotion() {
  if (!model || speaking || phase !== 'idle' || mood === 'angry') return;
  const now = Date.now();
  if (now - lastIdleMotionAt < 8000) return;
  lastIdleMotionAt = now;
  try {
    model.motion('Idle');
  } catch (error) {
    console.warn('Could not trigger idle motion', error);
  }
}

function triggerReactionMotion(nextMotion) {
  if (!model) return;
  try {
    if (nextMotion === 'bounce' || nextMotion === 'shake' || nextMotion === 'recoil') {
      model.motion('TapBody');
    } else {
      model.motion('Idle');
    }
  } catch (error) {
    console.warn('Could not trigger Live2D motion', error);
  }
}

function setPhase(nextPhase) {
  if (phase === nextPhase) return;
  phase = nextPhase;
  phaseStartedAt = performance.now();
}

window.setCompanionState = function setCompanionState(state) {
  if (!state || typeof state !== 'object') return;

  const nextMouthOpen = Number(state.mouthOpen ?? 0);
  const nextMood = String(state.mood ?? mood);
  const nextExpression = String(state.expression ?? expression);
  const nextMotion = String(state.motion ?? motion);
  const nextIntensity = Number(state.intensity ?? intensity);
  const nextDuration = Number(state.duration ?? duration);
  const nextSpeaking = Boolean(state.speaking);

  profile = state.profile && typeof state.profile === 'object' ? state.profile : profile;
  targetMouthOpen = clamp(nextMouthOpen, 0, 1);
  intensity = clamp(Number.isFinite(nextIntensity) ? nextIntensity : intensity, 0, 1);
  duration = clamp(Number.isFinite(nextDuration) ? nextDuration : duration, 0.4, 8);
  speaking = nextSpeaking;

  const affectChanged = nextMood !== mood || nextExpression !== expression || nextMotion !== motion;
  mood = nextMood;
  expression = nextExpression;
  motion = nextMotion;

  if (affectChanged) {
    applyExpression(expression);
    triggerReactionMotion(motion);
    setPhase('reacting');
  }

  if (speaking) {
    setPhase('speaking');
  } else if (phase === 'speaking') {
    setPhase('settling');
  }

  window.__companionDebugState = { mood, expression, motion, intensity, duration, speaking, targetMouthOpen, currentMouthOpen, phase, profile };
};

function motionOffsets(time) {
  const amount = clamp(intensity, 0, 1);
  const offsets = { x: 0, y: 0, angleX: Math.sin(time * 0.7) * 4, angleZ: Math.sin(time * 0.6) * 2, bodyX: Math.sin(time * 0.8) * 2 };

  if (motion === 'bounce') {
    offsets.y += Math.sin(time * 7.0) * 8 * amount;
    offsets.angleX += Math.sin(time * 1.6) * 7 * amount;
    offsets.bodyX += Math.sin(time * 2.1) * 5 * amount;
  } else if (motion === 'tilt') {
    offsets.angleX += 8 * amount;
    offsets.angleZ += -8 * amount;
    offsets.bodyX += 4 * amount;
  } else if (motion === 'shake') {
    const shake = Math.sin(time * 18.0) * 7 * amount;
    offsets.x += shake;
    offsets.angleZ += shake * 0.45;
    offsets.bodyX += -5 * amount + Math.sin(time * 7.0) * 3 * amount;
  } else if (motion === 'nod') {
    offsets.angleX += Math.sin(time * 4.0) * 4 * amount;
    offsets.y += Math.sin(time * 3.2) * 3 * amount;
  } else if (motion === 'leanIn') {
    offsets.y += Math.sin(time * 4.0) * 2 * amount;
    offsets.bodyX += 5 * amount;
  } else if (motion === 'recoil') {
    offsets.y += -8 * amount;
    offsets.angleX += -10 * amount;
    offsets.bodyX += -6 * amount;
  }

  if (speaking) {
    offsets.y += Math.sin(time * 6.0) * 5;
  }

  return offsets;
}

async function start() {
  try {
    if (!window.PIXI || !window.PIXI.live2d) {
      throw new Error('Live2D runtime scripts were not loaded.');
    }

    app = new PIXI.Application({
      view: canvas,
      resizeTo: stage,
      autoStart: true,
      antialias: true,
      transparent: true,
      backgroundAlpha: 0
    });

    model = await PIXI.live2d.Live2DModel.from(modelURL(), {
      autoInteract: false,
      idleMotionGroup: 'Idle'
    });

    app.stage.addChild(model);
    fitModel();
    const name = modelName();
    setStatus(`Live2D: ${name}`, 'loaded');
    notifyHost({ type: 'loaded', name });

    app.ticker.add(() => {
      currentMouthOpen += (targetMouthOpen - currentMouthOpen) * 0.35;
      if (!speaking && currentMouthOpen < 0.01) {
        currentMouthOpen = 0;
      }

      const elapsed = (performance.now() - phaseStartedAt) / 1000;
      if (phase === 'reacting' && elapsed > 0.6) {
        setPhase(speaking ? 'speaking' : 'settling');
      } else if (phase === 'settling' && elapsed > duration) {
        mood = 'calm';
        expression = 'neutral';
        motion = 'idle';
        intensity = 0.25;
        applyExpression(expression);
        setPhase('idle');
      }

      const time = performance.now() / 1000;
      const offsets = motionOffsets(time);
      model.x = app.renderer.width * 0.5 + offsets.x;
      model.y = app.renderer.height * 0.53 + offsets.y;

      for (const id of profile.lipSyncParameters || ['ParamMouthOpenY', 'ParamA']) {
        setParameter(id, currentMouthOpen);
      }
      applyExpression(expression);
      setParameter('ParamAngleX', offsets.angleX);
      setParameter('ParamAngleZ', offsets.angleZ);
      setParameter('ParamBodyAngleX', offsets.bodyX);
      window.__companionDebugState = { mood, expression, motion, intensity, duration, speaking, targetMouthOpen, currentMouthOpen, phase, profile };
      triggerIdleMotion();
    });

    window.addEventListener('resize', fitModel);
  } catch (error) {
    console.error(error);
    setStatus(`Live2D 로드 실패: ${error.message}`, 'error');
    notifyHost({ type: 'error', message: error.message });
  }
}

void start();
