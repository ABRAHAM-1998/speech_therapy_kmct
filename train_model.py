import os
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
import librosa

# Configuration
DATA_DIR = 'assets/VOICED_DATASET'
MODEL_DIR = 'assets/models'
SAMPLE_RATE = 16000
DURATION = 1.0 # Seconds
N_MFCC = 13
HOP_LENGTH = 512 
# Expected frames = ceil(16000 / 512) = ~32 frames for 1 second.
# Let's fix a max pad length to ensure consistent tensor shape.
MAX_FRAMES = 44 # generous padding for 1s + edge effects

def extract_statistical_features(audio_data):
    # audio_data is 16000 samples
    audio_data = audio_data.astype(np.float32)
    
    # 44 frames
    frame_size = len(audio_data) // MAX_FRAMES
    features_per_frame = []
    
    for i in range(MAX_FRAMES):
        start = i * frame_size
        end = start + frame_size
        frame = audio_data[start:end]
        
        if len(frame) == 0:
            features = np.zeros(N_MFCC)
        else:
            # Simple features computable in pure Dart
            rms = np.sqrt(np.mean(frame**2) + 1e-8)
            zcr = np.mean(np.diff(np.sign(frame)) != 0)
            mean = np.mean(np.abs(frame))
            var = np.var(frame)
            
            # Fill 13 features (duplicating/scaling to fill shape)
            features = [
                rms, zcr, mean, var,
                rms * 2, zcr * 2, mean * 2, var * 2,
                rms * 4, zcr * 4, mean * 4, var * 4,
                rms * 0.5
            ]
            
        features_per_frame.append(features)
        
    return np.array(features_per_frame) # (44, 13)

def load_data():
    X = []
    y = []
    
    files = [f for f in os.listdir(DATA_DIR) if f.endswith('.txt') and not f.endswith('-info.txt')]
    print(f"Found {len(files)} data files.")

    for filename in files:
        file_path = os.path.join(DATA_DIR, filename)
        try:
            # Load Raw Audio (simulating reading from .txt)
            raw_data = pd.read_csv(file_path, header=None).values.flatten()
            
            # Normalize length to 1 second raw audio first if needed, 
            # OR pass raw to mfcc and let it handle windows.
            # Best to pad raw audio to 16000 samples first to avoid empty MFCCs?
            if len(raw_data) > SAMPLE_RATE:
                raw_data = raw_data[:SAMPLE_RATE]
            else:
                raw_data = np.pad(raw_data, (0, SAMPLE_RATE - len(raw_data)), 'constant')
            
            # Extract Features
            mfcc_features = extract_statistical_features(raw_data)
            X.append(mfcc_features)
            
            # Load label
            info_filename = filename.replace('.txt', '-info.txt')
            info_path = os.path.join(DATA_DIR, info_filename)
            with open(info_path, 'r') as f:
                label = f.read().strip()
                y.append(label)
                
        except Exception as e:
            print(f"Skipping {filename}: {e}")

    return np.array(X), np.array(y)

def train_and_save():
    print("Loading data & Extracting MFCCs...")
    X, y = load_data()
    
    if len(X) == 0:
        print("No data found!")
        return

    print(f"Input Shape: {X.shape}") # Should be (N, 44, 13)

    # Encode labels
    le = LabelEncoder()
    y_enc = le.fit_transform(y)
    classes = le.classes_
    print(f"Classes: {classes}")
    
    # Save Labels
    with open(os.path.join(MODEL_DIR, 'labels.txt'), 'w') as f:
        f.write('\n'.join(classes))

    # Split
    X_train, X_test, y_train, y_test = train_test_split(X, y_enc, test_size=0.2, random_state=42)

    # Build Higher Accuracy Model (2D CNN for Spectrogram-like Data)
    model = tf.keras.models.Sequential([
        tf.keras.layers.Input(shape=(MAX_FRAMES, N_MFCC)),
        
        # Conv Layer 1
        tf.keras.layers.Conv1D(32, 3, activation='relu', padding='same'),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.MaxPooling1D(2),
        
        # Conv Layer 2
        tf.keras.layers.Conv1D(64, 3, activation='relu', padding='same'),
        tf.keras.layers.BatchNormalization(),
        tf.keras.layers.MaxPooling1D(2),

        # Dense Layers
        tf.keras.layers.GlobalAveragePooling1D(),
        tf.keras.layers.Dense(64, activation='relu'),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(len(classes), activation='softmax')
    ])

    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    
    print("Training model...")
    model.fit(X_train, y_train, epochs=15, validation_data=(X_test, y_test)) # More epochs for better fit

    # Convert to TFLite
    print("Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    save_path = os.path.join(MODEL_DIR, 'speech_classifier.tflite')
    with open(save_path, 'wb') as f:
        f.write(tflite_model)
    
    print(f"High Accuracy Model saved to {save_path}")

if __name__ == '__main__':
    train_and_save()
