use aes_gcm::{
    Aes256Gcm, Key, Nonce,
    aead::{AeadInPlace, KeyInit},
};
use sha2::{Digest, Sha256};

pub fn derive_aes_key(user_key: &str, file_key: &str, server_key: &str) -> [u8; 32] {
    let mut out = [0u8; 32];
    let k0 = Sha256::digest(server_key.as_bytes());
    let k1 = Sha256::digest(file_key.as_bytes());
    let k2 = Sha256::digest(user_key.as_bytes());

    let get_byte = |k: &[u8], idx: usize| if k.is_empty() { 0 } else { k[idx % k.len()] };

    for i in 0..32 {
        let b0 = get_byte(&k0, i) as u32;
        let b1 = get_byte(&k1, i) as u32;
        let b2 = get_byte(&k2, i) as u32;

        let shift_bytes = (b0 % 31) + 1;
        let x = b1 << shift_bytes;
        let y = b2 >> shift_bytes;

        let acc1 = (x ^ y).wrapping_add(b0).wrapping_mul(0x9E3779B9);
        let acc2 = x.wrapping_add(y).wrapping_sub(b0).wrapping_mul(0x85EBCA6B);

        let mix1 = (b0 ^ x.wrapping_mul(y)) ^ ((acc1 as u64) >> 32) as u32;
        let mix2 = x.wrapping_mul(y) ^ ((acc2 as u64) >> 32) as u32;

        let index = i % 32;
        out[index] ^= (mix1 ^ mix2) as u8;
    }

    out
}

pub fn construct_iv(username: &str) -> [u8; 12] {
    let mut hasher = Sha256::new();
    hasher.update(username.as_bytes());
    let hash = hasher.finalize();
    let mut iv = [0u8; 12];
    for i in 0..12 {
        let b1 = hash[i];
        let b2 = hash[i + 12];
        let b3 = if i + 24 < 32 { hash[i + 24] } else { 0 };
        iv[i] = b1 ^ b2 ^ b3;
    }
    iv
}

pub fn aes_gcm_encrypt(
    data: &[u8],
    user_key: &str,
    file_key: &str,
    server_key: &str,
    iv: &[u8; 12],
    aad: &[u8],
) -> Vec<u8> {
    let key_bytes = derive_aes_key(user_key, file_key, server_key);
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(iv);

    let mut buffer = data.to_vec();
    match cipher.encrypt_in_place_detached(nonce, aad, &mut buffer) {
        Ok(tag) => {
            buffer.extend_from_slice(&tag);
            buffer
        }
        Err(_) => data.to_vec(),
    }
}

pub fn aes_gcm_decrypt(
    data: &[u8],
    user_key: &str,
    file_key: &str,
    server_key: &str,
    iv: &[u8; 12],
    aad: &[u8],
) -> Result<Vec<u8>, aes_gcm::Error> {
    let key_bytes = derive_aes_key(user_key, file_key, server_key);
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(iv);

    if data.len() < 16 {
        return Err(aes_gcm::Error);
    }

    let mut ct = data[..data.len() - 16].to_vec();
    let tag = aes_gcm::Tag::from_slice(&data[data.len() - 16..]);

    cipher.decrypt_in_place_detached(nonce, aad, &mut ct, tag)?;
    Ok(ct)
}

pub fn aes_gcm_decrypt_no_verify(
    data: &[u8],
    user_key: &str,
    file_key: &str,
    server_key: &str,
    iv: &[u8; 12],
) -> Vec<u8> {
    let key_bytes = derive_aes_key(user_key, file_key, server_key);
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(iv);

    let mut buffer = data.to_vec();
    let _ = cipher.encrypt_in_place_detached(nonce, &[], &mut buffer);
    buffer
}

pub fn aes_gcm_verify_with_aad(
    data: &[u8],
    user_key: &str,
    file_key: &str,
    server_key: &str,
    iv: &[u8; 12],
    aad: &[u8],
) -> bool {
    let key_bytes = derive_aes_key(user_key, file_key, server_key);
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(iv);

    if data.len() < 16 {
        return false;
    }

    let mut ct = data[..data.len() - 16].to_vec();
    let tag = aes_gcm::Tag::from_slice(&data[data.len() - 16..]);

    cipher
        .decrypt_in_place_detached(nonce, aad, &mut ct, tag)
        .is_ok()
}
